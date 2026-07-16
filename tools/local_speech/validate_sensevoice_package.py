#!/usr/bin/env python3
"""Verify Sumi's local SenseVoice package before publication."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


REPOSITORY_ID = "Hilith/sumi-sensevoice-small-onnx-int8"
REQUIRED = {"model.int8.onnx", "tokens.txt"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    root = args.package.resolve()
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit("Missing manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("id") != REPOSITORY_ID or not manifest.get("version"):
        raise SystemExit("Unexpected package id or missing version")
    if manifest.get("runtime") != "sherpa-onnx-sensevoice":
        raise SystemExit("Unexpected speech runtime")
    declared = {entry.get("path") for entry in manifest.get("files", [])}
    if declared != REQUIRED:
        raise SystemExit("Package must contain exactly model.int8.onnx and tokens.txt")
    for entry in manifest["files"]:
        path = root / entry["path"]
        if not path.is_file() or path.stat().st_size != entry["sizeBytes"]:
            raise SystemExit(f"Size mismatch: {entry['path']}")
        if sha256(path) != entry["sha256"]:
            raise SystemExit(f"Checksum mismatch: {entry['path']}")
    if (root / "model.int8.onnx").stat().st_size < 50 * 1024 * 1024:
        raise SystemExit("Model file is unexpectedly small")
    if (root / "tokens.txt").stat().st_size < 10 * 1024:
        raise SystemExit("Token file is unexpectedly small")
    print("SenseVoice package validation passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
