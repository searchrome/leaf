#!/usr/bin/env python3
"""Inventory installed runtime package metadata without importing package code."""
import argparse
from datetime import datetime, timezone
from importlib import metadata
import json
from pathlib import Path


def inventory(site_packages):
    packages = []
    for distribution in metadata.distributions(path=[str(site_packages)]):
        fields = distribution.metadata
        license_text = fields.get("License") or ""
        packages.append({
            "name": fields["Name"], "version": distribution.version,
            "license_expression": fields.get("License-Expression"),
            "license_summary": license_text.splitlines()[0][:200] if license_text else None,
            "license_classifiers": [value for value in fields.get_all("Classifier", [])
                                    if value.startswith("License")],
            "requires": distribution.requires or [],
            "project_urls": fields.get_all("Project-URL", []),
        })
    return sorted(packages, key=lambda package: package["name"].lower())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", type=Path,
                        default=Path.home() / "Library/Application Support/Leaf/LocalKokoro/runtime")
    parser.add_argument("--output", type=Path, default=Path("dist/dependency-inventory.json"))
    args = parser.parse_args()
    locations = sorted((args.runtime / "lib").glob("python*/site-packages"))
    if len(locations) != 1:
        parser.error("Expected one installed Python runtime. Pass its directory with --runtime.")
    packages = inventory(locations[0])
    if not packages:
        parser.error("No installed packages were found.")
    report = {"format": 1, "collected_at": datetime.now(timezone.utc).isoformat(),
              "scope": "Installed optional Kokoro runtime; metadata is not a legal license determination",
              "packages": packages}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Inventoried {len(packages)} packages into {args.output}")


if __name__ == "__main__":
    main()
