#!/usr/bin/env python3
"""Read-only artifact checks. JSON evidence is not release qualification."""
import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=60)
    return {"status": result.returncode, "output": (result.stdout + result.stderr).strip()}


def inspect(app):
    checks = []
    def check(name, passed, detail):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})
    info_path = app / "Contents/Info.plist"
    try:
        info = plistlib.loads(info_path.read_bytes())
        executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
        if not executable.is_file() or executable.is_symlink():
            raise ValueError("Missing regular bundle executable")
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        check("bundle", False, str(error))
        return checks, {}
    check("version-identifiers", bool(info.get("CFBundleShortVersionString")) and bool(info.get("CFBundleVersion")), {"version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion")})
    debug_artifacts = [str(path.relative_to(app)) for path in app.rglob("*") if path.name.endswith((".debug.dylib", ".xctest"))]
    check("no-debug-artifacts", not debug_artifacts, debug_artifacts)
    check("bundle", info.get("CFBundleIdentifier") == "com.patrickbourget.Still", info.get("CFBundleIdentifier"))
    signature = command("/usr/bin/codesign", "--display", "--verbose=4", str(app))
    check("developer-id", signature["status"] == 0 and "Authority=Developer ID Application:" in signature["output"] and "TeamIdentifier=not set" not in signature["output"], signature)
    check("hardened-runtime", any("flags=" in line and "runtime" in line for line in signature["output"].splitlines()), signature["output"])
    verification = command("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))
    check("signature-integrity", verification["status"] == 0, verification)
    entitlements = command("/usr/bin/codesign", "--display", "--entitlements", "-", str(app))
    try:
        text = entitlements["output"]
        start = text.find("<?xml")
        end = text.find("</plist>")
        values = plistlib.loads(text[start:end + len("</plist>")].encode()) if start >= 0 and end >= 0 else {}
        forbidden = [key for key in ("com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation", "com.apple.security.cs.allow-jit", "com.apple.security.cs.allow-unsigned-executable-memory", "com.apple.security.cs.disable-executable-page-protection", "com.apple.security.cs.allow-dyld-environment-variables") if values.get(key)]
        check("no-debug-runtime-exceptions", entitlements["status"] == 0 and not forbidden, {"entitlements": values, "forbidden": forbidden})
    except (ValueError, plistlib.InvalidFileException) as error:
        check("no-debug-runtime-exceptions", False, str(error))
    privacy_path = app / "Contents/Resources/PrivacyInfo.xcprivacy"
    expected = {"NSPrivacyAccessedAPICategoryDiskSpace": {"85F4.1"}, "NSPrivacyAccessedAPICategoryFileTimestamp": {"3B52.1"}, "NSPrivacyAccessedAPICategorySystemBootTime": {"35F9.1"}, "NSPrivacyAccessedAPICategoryUserDefaults": {"CA92.1"}}
    try:
        privacy = plistlib.loads(privacy_path.read_bytes())
        actual = {row["NSPrivacyAccessedAPIType"]: set(row["NSPrivacyAccessedAPITypeReasons"]) for row in privacy["NSPrivacyAccessedAPITypes"]}
        check("privacy-purpose-declarations", all(reasons <= actual.get(category, set()) for category, reasons in expected.items()) and privacy.get("NSPrivacyTracking") is False and privacy.get("NSPrivacyCollectedDataTypes") == [], {key: sorted(value) for key, value in actual.items()})
    except (OSError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        check("privacy-purpose-declarations", False, str(error))
    architectures = command("/usr/bin/lipo", "-archs", str(executable))
    check("architecture-readable", architectures["status"] == 0, architectures)
    # Validation only: neither command submits nor staples, changes trust, or launches the app.
    staple = command("/usr/bin/xcrun", "stapler", "validate", str(app))
    check("stapled-notary-ticket", staple["status"] == 0, staple)
    gatekeeper = command("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=4", str(app))
    check("gatekeeper-assessment", gatekeeper["status"] == 0 and "Notarized Developer ID" in gatekeeper["output"], gatekeeper)
    return checks, {"version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"), "minimumOS": info.get("LSMinimumSystemVersion"), "architectures": architectures["output"], "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    args = parser.parse_args()
    app = args.app.resolve(strict=True)
    checks, artifact = inspect(app)
    passed = all(check["passed"] for check in checks)
    report = {"schema": 1, "capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(), "artifact": artifact, "checks": checks, "artifactPreflightPassed": passed, "releaseQualified": False, "remainingGates": ["Approved feature/support evidence manifest", "#14 personal validation", "#34 performance qualification", "Manual accessibility/localization/display coverage", "Clean-machine install/uninstall and signed manual-update exercise"]}
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"artifactPreflightPassed": False, "releaseQualified": False, "error": str(error)}))
        sys.exit(2)
