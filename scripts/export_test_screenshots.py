"""Export named test screenshots without downloading the complete Xcode result bundle."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def export(bundle, destination):
    if not bundle.is_dir():
        print("No test result bundle to export.")
        return
    destination.mkdir(parents=True, exist_ok=True)
    version = subprocess.check_output(["xcodebuild", "-version"], text=True)
    xcode_major = int(re.search(r"Xcode (\d+)", version).group(1))
    legacy_flags = ["--legacy"] if xcode_major >= 16 else []
    pending, visited, exported, manifest = [None], set(), set(), []
    while pending:
        reference = pending.pop()
        if reference in visited:
            continue
        visited.add(reference)
        command = ["xcrun", "xcresulttool", "get"] + legacy_flags + ["--path", str(bundle), "--format", "json"]
        if reference:
            command += ["--id", reference]
        data = json.loads(subprocess.check_output(command))

        def walk(node):
            if isinstance(node, list):
                for child in node:
                    walk(child)
            elif isinstance(node, dict):
                for key in ("testsRef", "summaryRef"):
                    identifier = node.get(key, {}).get("id", {}).get("_value")
                    if identifier and identifier not in visited:
                        pending.append(identifier)
                kind = node.get("uniformTypeIdentifier", {}).get("_value")
                identifier = node.get("payloadRef", {}).get("id", {}).get("_value")
                if kind in ("public.png", "public.jpeg") and identifier and identifier not in exported:
                    exported.add(identifier)
                    name = node.get("name", {}).get("_value", "screenshot")
                    safe_name = re.sub(r"[^\w\-\u4e00-\u9fff]", "_", name)[:100]
                    extension = ".png" if kind == "public.png" else ".jpg"
                    path = destination / (f"{len(manifest) + 1:02d}-" + safe_name + extension)
                    subprocess.run(["xcrun", "xcresulttool", "export"] + legacy_flags + ["--path", str(bundle),
                                    "--id", identifier, "--type", "file", "--output-path", str(path)], check=True)
                    manifest.append({"name": name, "file": path.name})
                for child in node.values():
                    walk(child)

        walk(data)
    (destination / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Exported {len(manifest)} screenshots.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    export(arguments.bundle, arguments.destination)
