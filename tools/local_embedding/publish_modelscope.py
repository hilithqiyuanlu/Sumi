#!/usr/bin/env python3
"""Publish a previously validated package to ModelScope, safely by default."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--repo", required=True, help="Explicit ModelScope repository, e.g. Hilith/bge-small-zh-v1.5-onnx-int8")
    parser.add_argument("--revision", required=True, help="Explicit immutable release tag, e.g. v1.0.0")
    parser.add_argument("--publish", action="store_true", help="Actually upload after validation")
    args = parser.parse_args()
    package = args.package.resolve()
    manifest = package / "manifest.json"
    if not manifest.is_file():
        raise SystemExit("Package must contain manifest.json")
    spec = json.loads(manifest.read_text(encoding="utf-8"))
    if spec.get("id") != args.repo:
        raise SystemExit("Manifest package id must match --repo")

    validate = [sys.executable, str(Path(__file__).with_name("validate_package.py")), str(package)]
    if subprocess.run(validate, check=False).returncode != 0:
        raise SystemExit("Refusing to publish a package that did not pass offline validation")

    command = ["modelscope", "upload", "--repo-id", args.repo, "--revision", args.revision, "--local-dir", str(package)]
    if not args.publish:
        print("DRY RUN: no credentials read and no upload performed.")
        print(" ".join(command))
        return 0
    token = os.environ.get("MODELSCOPE_API_TOKEN")
    if not token:
        raise SystemExit("Set MODELSCOPE_API_TOKEN before using --publish")
    environment = dict(os.environ)
    environment["MODELSCOPE_API_TOKEN"] = token
    print(f"Uploading validated package to {args.repo}@{args.revision}")
    return subprocess.run(command, env=environment, check=False).returncode


if __name__ == "__main__":
    sys.exit(main())
