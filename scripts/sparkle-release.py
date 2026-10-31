#!/usr/bin/env python3
"""Local Sparkle release generation; private keys are read only by Sparkle's Keychain tools."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

SPARKLE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
TEAM = '8F5K2ZRP5T'


def run(*args):
    result = subprocess.run([str(a) for a in args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        # Never echo tool output: a failed signing tool must not expose key material.
        raise ValueError(f'{Path(args[0]).name} failed (exit {result.returncode})')
    return result.stdout.strip()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()


def info(app):
    with (app / 'Contents/Info.plist').open('rb') as stream:
        value = plistlib.load(stream)
    if value.get('CFBundleIdentifier') != 'com.patrickbourget.CacheDrop':
        raise ValueError('unexpected application bundle identity')
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value['CFBundleShortVersionString']):
        raise ValueError('release version must be stable x.y.z')
    if not re.fullmatch(r'[1-9][0-9]*', value['CFBundleVersion']):
        raise ValueError('release build must be a positive integer')
    return value


def prerequisites(args, public):
    try:
        if len(base64.b64decode(public, validate=True)) != 32:
            raise ValueError()
    except (ValueError, TypeError):
        raise ValueError('configure a valid public EdDSA key in CacheDrop/UpdateInfo.plist')
    parsed = urlsplit(args.artifact_base_url)
    if parsed.scheme != 'https' or not parsed.netloc or parsed.query or parsed.fragment or parsed.username:
        raise ValueError('artifact base URL must be an immutable HTTPS directory without credentials, query or fragment')
    if not args.artifact_base_url.endswith('/'):
        raise ValueError('artifact base URL must end in /')
    if not args.release_notes.is_file() or args.release_notes.suffix != '.html' or not args.release_notes.read_text().strip():
        raise ValueError('--release-notes requires a nonempty reviewed .html file')
    for name in ('generate_keys', 'sign_update', 'generate_appcast'):
        if not (args.tools / name).is_file():
            raise ValueError(f'missing Sparkle tool: {name}; use the pinned 2.10.1 distribution')
    actual = run(args.tools / 'generate_keys', '--account', args.account, '-p')
    if actual != public:
        raise ValueError('Keychain signing public key does not match the embedded public EdDSA key')


def check_feed(feed, args, value, signature):
    root = ET.parse(feed).getroot()
    items = root.findall('./channel/item')
    if len(items) != 1:
        raise ValueError('generated feed must contain exactly this full update')
    item = items[0]
    enclosure = item.find('enclosure')
    if enclosure is None:
        raise ValueError('generated feed has no enclosure')
    expected = {'url': args.artifact_base_url + args.dmg.name, 'length': str(args.dmg.stat().st_size),
                SPARKLE + 'edSignature': signature}
    if any(enclosure.get(key) != val for key, val in expected.items()):
        raise ValueError('generated enclosure does not match the final DMG URL, length or signature')
    if (item.findtext(SPARKLE + 'version') != value['CFBundleVersion'] or
            item.findtext(SPARKLE + 'shortVersionString') != value['CFBundleShortVersionString']):
        raise ValueError('generated versions do not match the app')
    if args.release_notes.read_text().strip() not in (item.findtext('description') or ''):
        raise ValueError('generated feed does not embed the reviewed release notes')
    if item.findall('.//' + SPARKLE + 'delta') or item.find(SPARKLE + 'deltas') is not None:
        raise ValueError('only full DMG updates are supported')


def generate(args):
    value = info(args.app)
    prerequisites(args, value.get('SUPublicEDKey'))
    if args.dmg.name != f"CacheDrop-{value['CFBundleShortVersionString']}.dmg":
        raise ValueError('DMG filename must match the stable marketing version')
    original = digest(args.dmg)
    signature = run(args.tools / 'sign_update', '--account', args.account, '-p', args.dmg)
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('sign_update returned an invalid EdDSA signature')
    with tempfile.TemporaryDirectory(prefix='cachedrop-appcast-') as temporary:
        staging = Path(temporary)
        shutil.copy2(args.dmg, staging / args.dmg.name)
        shutil.copy2(args.release_notes, staging / (args.dmg.stem + '.html'))
        feed = staging / 'appcast.xml'
        run(args.tools / 'generate_appcast', '--account', args.account, '--maximum-deltas', '0',
            '--embed-release-notes', '--download-url-prefix', args.artifact_base_url, '-o', feed, staging)
        check_feed(feed, args, value, signature)
        run(args.tools / 'sign_update', '--account', args.account, '--verify', args.dmg, signature)
        if digest(args.dmg) != original:
            raise ValueError('final DMG changed after signing')
        identity = dict(version=value['CFBundleShortVersionString'], build=value['CFBundleVersion'],
                        bundleID=value['CFBundleIdentifier'], teamID=TEAM, commit=args.commit,
                        filename=args.dmg.name, url=args.artifact_base_url + args.dmg.name,
                        length=args.dmg.stat().st_size, sha256=original, edSignature=signature,
                        publicKey=value['SUPublicEDKey'], releaseNotesSHA256=digest(args.release_notes))
        # Do not leave successful-looking metadata after any tool or validation failure.
        shutil.copy2(feed, args.dmg.parent / 'appcast.xml')
        shutil.copy2(args.release_notes, args.dmg.parent / (args.dmg.stem + '.html'))
        (args.dmg.parent / 'release-identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    print('Verified final DMG EdDSA signature and generated local appcast.xml / release-identity.json; nothing uploaded.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('preflight', 'generate', 'verify'))
    parser.add_argument('--tools', type=Path, required=True, help='bin directory from pinned Sparkle 2.10.1 distribution')
    parser.add_argument('--account', default='ed25519')
    parser.add_argument('--artifact-base-url', required=True)
    parser.add_argument('--release-notes', type=Path, required=True, help='reviewed HTML fragment, embedded in appcast')
    parser.add_argument('--plist', type=Path)
    parser.add_argument('--app', type=Path)
    parser.add_argument('--dmg', type=Path)
    parser.add_argument('--commit')
    args = parser.parse_args()
    try:
        if args.operation == 'preflight':
            with args.plist.open('rb') as stream:
                prerequisites(args, plistlib.load(stream).get('SUPublicEDKey'))
        elif args.operation == 'generate':
            if not args.commit:
                raise ValueError('--commit is required')
            generate(args)
        else:
            value = info(args.app)
            prerequisites(args, value.get('SUPublicEDKey'))
            identity = json.loads((args.dmg.parent / 'release-identity.json').read_text())
            expected = dict(version=value['CFBundleShortVersionString'], build=value['CFBundleVersion'],
                            bundleID=value['CFBundleIdentifier'], teamID=TEAM, filename=args.dmg.name,
                            url=args.artifact_base_url + args.dmg.name, length=args.dmg.stat().st_size,
                            sha256=digest(args.dmg), publicKey=value['SUPublicEDKey'],
                            releaseNotesSHA256=digest(args.release_notes))
            if any(identity.get(key) != val for key, val in expected.items()):
                raise ValueError('artifact identity does not match the app, final DMG, URL or release notes')
            check_feed(args.dmg.parent / 'appcast.xml', args, value, identity['edSignature'])
            run(args.tools / 'sign_update', '--account', args.account, '--verify', args.dmg, identity['edSignature'])
            print('Final DMG identity, feed metadata, release notes and EdDSA signature verified.')
    except (ValueError, OSError, KeyError, ET.ParseError) as error:
        parser.exit(1, f'sparkle-release: {error}\n')


if __name__ == '__main__':
    main()
