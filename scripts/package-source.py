#!/usr/bin/env python3
"""Export a reviewed source tree without history, runtime data, or credentials."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parent.parent
ROOT_FILES = ("Package.swift", "README.md", ".gitignore", "LICENSE")
DOC_FILES = ("docs/ARCHITECTURE.md", "docs/RELEASE.md", "docs/THIRD_PARTY_NOTICES.md", "docs/DEPENDENCIES.md",
             "docs/dependency-inventory.json", "docs/dependency-vulnerabilities.json")
SOURCE_DIRS = {"Sources": {".swift", ".py", ".txt"}, "Tests": {".swift"},
               "packaging": {".swift", ".plist"}, "scripts": {".sh", ".py"}}
SECRET = re.compile(rb"sk-or-v1-[a-fA-F0-9]{64}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")


def source_files():
    files = {ROOT / name for name in ROOT_FILES + DOC_FILES if (ROOT / name).is_file()}
    for directory, extensions in SOURCE_DIRS.items():
        files.update(path for path in (ROOT / directory).rglob("*")
                     if path.suffix in extensions and "__pycache__" not in path.parts)
    for path in sorted(files):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Refusing non-regular source file: {path.relative_to(ROOT)}")
        # Resolve paths as well, so a symlinked parent cannot pull in external data.
        if not path.resolve().is_relative_to(ROOT):
            raise ValueError(f"Source path leaves the project: {path.relative_to(ROOT)}")
        data = path.read_bytes()
        if SECRET.search(data):
            raise ValueError(f"Possible private credential in {path.relative_to(ROOT)}")
        yield path.relative_to(ROOT).as_posix(), data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-license", action="store_true",
                        help="Refuse to create a sale package until a LICENSE is supplied")
    args = parser.parse_args()
    has_license = (ROOT / "LICENSE").is_file() and bool((ROOT / "LICENSE").read_text().strip())
    if args.require_license and not has_license:
        parser.error("Add your approved buyer license as LICENSE before exporting for sale.")
    output = ROOT / "dist" / ("Leaf-source.zip" if has_license else "Leaf-source-review.zip")
    output.parent.mkdir(parents=True, exist_ok=True)
    files = list(source_files())
    manifest = {"format": 1, "license_supplied": has_license,
                "files": {name: hashlib.sha256(data).hexdigest() for name, data in files}}
    temporary = output.with_suffix(".zip.tmp")
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in files:
                archive.writestr("Leaf/" + name, data)
            archive.writestr("Leaf/SOURCE_MANIFEST.json", json.dumps(manifest, indent=2) + "\n")
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Created {output} ({len(files)} source files)")
    if not has_license:
        print("Review package only: copyright attribution and buyer license terms still need to be supplied.")


if __name__ == "__main__":
    main()
