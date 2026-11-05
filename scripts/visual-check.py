#!/usr/bin/env python3
"""Opt-in window captures and exact comparisons. See docs/agents/ui-testing.md."""
import argparse
import json
import math
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Each is a `case` in VisualCaptureUITests, which builds its fixtures and the pages it captures (#728).
SCENARIOS = ("overview", "audio-software", "photo-video")


def output_folder(destination):
    """The folder captures go to, checked before building; None means a fresh temp folder once they exist."""
    if destination is None:
        return None
    destination = destination.resolve()
    if destination.is_relative_to(ROOT):
        raise ValueError("Choose a new output directory outside this checkout")
    if destination.exists():
        raise ValueError(f"{destination} already exists: name a new folder, or leave out the folder for a fresh one")
    return destination


def capture_plan(plan_bytes, scenario):
    """The generated test plan with the capture test switched on for `scenario`."""
    plan = plistlib.loads(plan_bytes)
    # Xcode emits v1 for schemes without a test plan, v2 for test configurations.
    candidates = [target for config in plan.get("TestConfigurations", []) for target in config["TestTargets"]]
    candidates += [value for value in plan.values() if isinstance(value, dict)]
    targets = [target for target in candidates if target.get("BlueprintName") == "CacheDropUITests"]
    if len(targets) != 1:
        raise ValueError("Expected exactly one UI test target")
    targets[0].setdefault("EnvironmentVariables", {}).update(CACHEDROP_VISUAL_CAPTURE="1", CACHEDROP_VISUAL_SCENARIO=scenario)
    return plistlib.dumps(plan)


def deliver(source, destination, scenario):
    """Moves the runner's captures to `destination`, or to a fresh temp folder when it is None, and returns where."""
    if destination is None:
        destination = Path(tempfile.mkdtemp(prefix=f"cachedrop-visual-{scenario}-")).resolve()
    shutil.copytree(source, destination, dirs_exist_ok=True)
    shutil.rmtree(source)
    return destination


def capture(destination, scenario):
    destination = output_folder(destination)
    env = dict(os.environ)
    env.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
    products = ROOT / ".build/visual-build/Build/Products"
    log = ROOT / ".build/visual-capture.log"
    log.parent.mkdir(parents=True, exist_ok=True)

    def run(args):
        with log.open("w") as stream:
            result = subprocess.run(["xcodebuild", *args], cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode:
            raise ValueError(f"xcodebuild failed; see {log}\n" + "\n".join(log.read_text().splitlines()[-20:]))

    run(["build-for-testing", "-project", "CacheDrop/CacheDrop.xcodeproj", "-scheme", "CacheDrop",
         "-configuration", "Debug", "-destination", "platform=macOS", "-derivedDataPath", ".build/visual-build"])
    plans = list(products.glob("CacheDrop_*.xctestrun"))
    if len(plans) != 1:
        raise ValueError(f"Expected one CacheDrop xctestrun, found {len(plans)}")
    # Keep __TESTROOT__ beside the original products; never change the generated plan in place.
    with tempfile.NamedTemporaryFile(dir=products, suffix=".xctestrun") as modified:
        modified.write(capture_plan(plans[0].read_bytes(), scenario)); modified.flush()
        run(["test-without-building", "-xctestrun", modified.name, "-destination", "platform=macOS",
             "-collect-test-diagnostics", "never", "-parallel-testing-enabled", "NO",
             "-only-testing:CacheDropUITests/VisualCaptureUITests/testCaptureWindow"])
    matches = re.findall(r"^VISUAL_CAPTURE_DIR=(.+)$", log.read_text(), re.MULTILINE)
    if len(matches) != 1:
        raise ValueError(f"Capture did not finish; see {log}")
    source = Path(matches[0].strip())
    if not source.is_dir() or not source.name.startswith("CacheDropVisual-"):
        raise ValueError("Invalid capture output")
    print(f"{scenario}: window captures and explicit masks in {deliver(source, destination, scenario)}")


def manifest_names(manifests):
    """The images to compare: both captures must hold the same ones, so both are of one scenario."""
    names = set(manifests[0])
    if not names or any(set(manifest) != names for manifest in manifests):
        raise ValueError("Both manifests must hold the same pages: compare captures of one scenario")
    return sorted(names)


def compare(before, after, tolerance):
    from PIL import Image, ImageChops, ImageDraw
    manifests = [json.loads((folder / "manifest.json").read_text()) for folder in (before, after)]
    results = []
    for name in manifest_names(manifests):
        with Image.open(before / name) as a, Image.open(after / name) as b:
            if a.size != b.size:
                raise ValueError(f"{name}: image dimensions differ: {a.size} vs {b.size}")
            delta = ImageChops.difference(a.convert("RGBA"), b.convert("RGBA"))
        mask = Image.new("1", delta.size, 0)
        draw = ImageDraw.Draw(mask)
        if manifests[0][name]["width"] != manifests[1][name]["width"] or manifests[0][name]["height"] != manifests[1][name]["height"]:
            raise ValueError(f"{name}: window dimensions differ")
        for manifest in manifests:
            record = manifest[name]
            width, height = record["width"], record["height"]
            if not all(math.isfinite(v) and v > 0 for v in (width, height)):
                raise ValueError(f"{name}: invalid window size")
            for rect in record["masks"]:
                x, y, w, h = (rect[key] for key in ("x", "y", "width", "height"))
                if not rect["reason"] or not all(math.isfinite(v) for v in (x, y, w, h)) or min(x, y) < 0 or min(w, h) <= 0 or x + w > width + .01 or y + h > height + .01:
                    raise ValueError(f"{name}: invalid explicit mask")
                draw.rectangle((math.floor(x * delta.width / width), math.floor(y * delta.height / height),
                                math.ceil((x + w) * delta.width / width) - 1, math.ceil((y + h) * delta.height / height) - 1), fill=1)
        excluded = mask.histogram()[1]
        if excluded == delta.width * delta.height:
            raise ValueError(f"{name}: masks exclude the whole image")
        raw_changed = sum(max(pixel) > tolerance for pixel in delta.getdata())
        delta.paste((0, 0, 0, 0), mask=mask)
        results.append({"image": name, "raw_changed_pixels": raw_changed,
                        "unmasked_changed_pixels": sum(max(pixel) > tolerance for pixel in delta.getdata()),
                        "maximum_unmasked_channel_difference": max(high for low, high in delta.getextrema()),
                        "excluded_pixels": excluded, "tolerance": tolerance})
    print(json.dumps(results, indent=2))
    return int(any(row["unmasked_changed_pixels"] for row in results))


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    take = commands.add_parser("capture", help="Drives the screen; run only when the Mac is free")
    take.add_argument("--scenario", choices=SCENARIOS, default="overview", help="What to capture (default: overview)")
    take.add_argument("destination", type=Path, nargs="?", help="A new folder outside the checkout (default: a fresh temp folder)")
    diff = commands.add_parser("compare", help="No screen access; requires Pillow")
    diff.add_argument("before", type=Path)
    diff.add_argument("after", type=Path)
    diff.add_argument("--tolerance", type=int, choices=range(256), default=0, metavar="0..255")
    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "capture":
            capture(args.destination, args.scenario)
            return 0
        return compare(args.before, args.after, args.tolerance)
    except ImportError:
        parser.exit(2, "Comparison requires Pillow: install it in a Python virtual environment.\n")
    except (ValueError, OSError, KeyError, TypeError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
