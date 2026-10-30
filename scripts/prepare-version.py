#!/usr/bin/env python3
"""Prepare version settings only; building remains a separate, committed-HEAD operation."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


PROJECT = Path('CacheDrop/CacheDrop.xcodeproj/project.pbxproj')
STABLE_VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)')


def stable_version(value):
    match = STABLE_VERSION.fullmatch(value)
    if not match:
        raise ValueError('version must be a stable x.y.z number, without leading zeros or a prerelease suffix')
    return tuple(map(int, match.groups()))


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()


def configuration_range(source, identifier):
    """Locate the validated configuration without reformatting the owner's project file."""
    start = re.search(r'\b' + re.escape(identifier) + r'(?:\s*/\*.*?\*/)?\s*=\s*\{', source)
    if start is None:
        raise ValueError(f'cannot locate build configuration {identifier}')
    depth = 1
    for token in re.finditer(r'"(?:\\.|[^"\\])*"|/\*.*?\*/|//[^\n]*|[{}]', source[start.end():], re.DOTALL):
        if token.group() == '{':
            depth += 1
        elif token.group() == '}':
            depth -= 1
            if depth == 0:
                return start.end(), start.end() + token.start()
    raise ValueError(f'incomplete build configuration {identifier}')


def prepare(version):
    requested = stable_version(version)
    repo = Path(git(Path(__file__).resolve().parent, 'rev-parse', '--show-toplevel'))
    project = repo / PROJECT
    git(repo, 'ls-files', '--error-unmatch', str(PROJECT))
    if git(repo, 'status', '--porcelain', '--', str(PROJECT)):
        raise ValueError('the Xcode project has local changes; review and commit or stash them before preparing a version')
    source = project.read_bytes().decode('utf-8')
    parsed = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project)], text=True))
    objects = parsed['objects']
    targets = [item for item in objects.values() if item.get('isa') == 'PBXNativeTarget'
               and item.get('name') == 'CacheDrop' and item.get('productType') == 'com.apple.product-type.application']
    if len(targets) != 1:
        raise ValueError('expected exactly one CacheDrop application target')
    identifiers = objects[targets[0]['buildConfigurationList']]['buildConfigurations']
    if not identifiers:
        raise ValueError('CacheDrop has no build configurations')
    configurations = [objects[identifier]['buildSettings'] for identifier in identifiers]
    current_versions = {settings['MARKETING_VERSION'] for settings in configurations}
    if len(current_versions) != 1:
        raise ValueError('CacheDrop app configurations have inconsistent marketing versions')
    if requested <= stable_version(current_versions.pop()):
        raise ValueError('the new marketing version must be greater than the current version')
    builds = [str(settings['CURRENT_PROJECT_VERSION']) for settings in configurations]
    if any(re.fullmatch(r'[1-9][0-9]*', build) is None for build in builds):
        raise ValueError('CacheDrop build numbers must be positive integers')
    build = str(max(map(int, builds)) + 1)
    replacements = []
    for identifier in identifiers:
        begin, end = configuration_range(source, identifier)
        for key, value in [('MARKETING_VERSION', version), ('CURRENT_PROJECT_VERSION', build)]:
            matches = list(re.finditer(r'\b' + key + r'\s*=\s*("[^"\n]*"|[^;\s]+)\s*;', source[begin:end]))
            if len(matches) != 1:
                raise ValueError(f'expected one explicit {key} in configuration {identifier}')
            match = matches[0]
            replacements.append((begin + match.start(1), begin + match.end(1), value))
    prepared = source
    for begin, end, value in sorted(replacements, reverse=True):
        prepared = prepared[:begin] + value + prepared[end:]
    # One atomic replacement after every configuration and input has been validated.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', newline='', dir=project.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(prepared)
        temporary.chmod(project.stat().st_mode)
        os.replace(temporary, project)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(f'Prepared CacheDrop {version} ({build}) in {PROJECT}.')
    print('Review the diff and commit it, then run scripts/release.sh separately from a clean checkout.')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('expected one explicit stable x.y.z version')
        prepare(sys.argv[1])
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f'release.sh: {error}', file=sys.stderr)
        sys.exit(1)
