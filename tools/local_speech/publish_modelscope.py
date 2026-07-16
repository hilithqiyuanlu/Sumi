#!/usr/bin/env python3
"""Publish a verified SenseVoice package to ModelScope; dry-run by default."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


REPOSITORY_ID = "Hilith/sumi-sensevoice-small-onnx-int8"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--revision", required=True, help="Release tag, e.g. v1.0.0")
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    package = args.package.resolve()
    validate = [
        sys.executable,
        str(Path(__file__).with_name("validate_sensevoice_package.py")),
        str(package),
    ]
    if subprocess.run(validate, check=False).returncode != 0:
        raise SystemExit("Refusing to publish an invalid package")
    command = [
        "modelscope", "upload", "--repo-id", REPOSITORY_ID,
        "--revision", args.revision, "--local-dir", str(package),
    ]
    if not args.publish:
        print("DRY RUN: no credentials read and no upload performed.")
        print(" ".join(command))
        return 0
    if not os.environ.get("MODELSCOPE_API_TOKEN"):
        raise SystemExit("Set MODELSCOPE_API_TOKEN before using --publish")
    return subprocess.run(command, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
