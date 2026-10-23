#!/usr/bin/env python3
"""Prepare one explicit hosted native-authorization journey; never change OS settings."""
import getpass
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import uuid


def main():
    env = os.environ
    if not (env.get('GITHUB_ACTIONS') == 'true'
            and env.get('RUNNER_ENVIRONMENT') == 'github-hosted'
            and env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch'
            and env.get('REQUESTED_SUITE') == 'alerts-native'
            and platform.system() == 'Darwin' and getpass.getuser() == 'runner'
            and os.geteuid() != 0):
        raise SystemExit('Refused: native authorization requires the explicit fresh hosted workflow.')
    if any(name in env for name in ('STILL_TEST_STATE_ROOT', 'STILL_TEST_STATE_ID')):
        raise SystemExit('Refused: ordinary disposable-test overrides are not native qualification.')
    home = Path.home()
    for path in (home / 'Library/Application Support/Still',
                 home / 'Library/Preferences/com.patrickbourget.Still.plist'):
        if path.exists() or path.is_symlink():
            raise SystemExit('Refused: app state already exists. No reset or workaround is allowed.')
    if shutil.disk_usage(home).free < 2_000_000_000:
        raise SystemExit('Refused: insufficient headroom for a genuine 1 GB threshold experiment.')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    if source != env.get('GITHUB_SHA') or len(source) != 40:
        raise SystemExit('Refused: checked out source does not match workflow commit.')
    products = Path('.build/alerts-native/Build/Products').resolve()
    runs = list(products.glob('Still_*.xctestrun'))
    if len(runs) != 1:
        raise SystemExit('Refused: expected exactly one generated Still xctestrun.')
    data = plistlib.loads(runs[0].read_bytes())
    # This exact format was observed from build-for-testing; reject future layout changes.
    target = data.get('StillUITests')
    if not (isinstance(target, dict) and target.get('BlueprintName') == 'StillUITests'
            and target.get('IsUITestBundle') is True
            and isinstance(target.get('EnvironmentVariables'), dict)):
        raise SystemExit('Refused: generated runner environment interface is unrecognized.')
    app = products / 'Debug/Still.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.patrickbourget.Still':
        raise SystemExit('Refused: unexpected application identity.')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['codesign', '-d', '--verbose=4', str(app)],
                               check=True, capture_output=True, text=True).stderr
    probe = str(uuid.uuid4())
    temporary = Path(env['RUNNER_TEMP']).resolve(strict=True)
    report = temporary / ('still-alerts-native-' + probe)
    report.mkdir(mode=0o700)
    guards = {
        'STILL_ALERTS_NATIVE_QUALIFICATION': '1', 'STILL_ALERTS_PROBE_ID': probe,
        'STILL_ALERTS_SOURCE_COMMIT': source, 'STILL_ALERTS_REPORT_DIRECTORY': str(report),
        'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
        'RUNNER_TEMP': str(temporary),
    }
    target['EnvironmentVariables'].update(guards)
    for key in ('EnvironmentVariables', 'UITargetAppEnvironmentVariables'):
        for name in ('STILL_TEST_STATE_ROOT', 'STILL_TEST_STATE_ID'):
            target.get(key, {}).pop(name, None)
    prepared = products / 'Still-alerts-native.xctestrun'
    prepared.write_bytes(plistlib.dumps(data))
    manifest = {
        'probeID': probe, 'sourceCommit': source,
        'runURL': f"https://github.com/{env['GITHUB_REPOSITORY']}/actions/runs/{env['GITHUB_RUN_ID']}",
        'os': subprocess.check_output(['sw_vers'], text=True),
        'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True),
        'architecture': platform.machine(), 'applicationBundleID': info['CFBundleIdentifier'],
        'adHocSignature': signature, 'signatureVerified': True,
        'freshNormalAppState': True, 'runnerEnvironmentInjection': 'StillUITests.EnvironmentVariables',
        'notificationDeliveryQualified': False, 'loginRegistrationQualified': False,
        'authorizationAttemptLimit': 1,
    }
    (report / 'environment.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Prepared guarded runner: {prepared}')


if __name__ == '__main__':
    main()
