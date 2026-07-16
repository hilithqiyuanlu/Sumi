#!/usr/bin/env python3
"""Build Sumi's verified local SenseVoice package from an official release.

The model binary is deliberately written outside this repository. This tool
downloads one pinned public upstream archive, keeps only the runtime files
needed by sherpa-onnx, and creates the manifest accepted by the Sumi client.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tarfile
import tempfile
import urllib.request
from datetime import UTC, datetime
from pathlib import Path


REPOSITORY_ID = "Hilith/sumi-sensevoice-small-onnx-int8"
UPSTREAM_VERSION = "2025-09-09"
UPSTREAM_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"
    "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09.tar.bz2"
)
REQUIRED = ("model.int8.onnx", "tokens.txt")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_files(root: Path) -> list[dict[str, object]]:
    return [
        {
            "path": file.relative_to(root).as_posix(),
            "sizeBytes": file.stat().st_size,
            "sha256": sha256(file),
        }
        for file in sorted(root.iterdir())
        if file.is_file() and file.name != "manifest.json"
    ]


def find_required(root: Path, name: str) -> Path:
    matches = list(root.rglob(name))
    if len(matches) != 1:
        raise SystemExit(f"Expected exactly one {name}, found {len(matches)}")
    return matches[0]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--upstream-url", default=UPSTREAM_URL)
    parser.add_argument("--archive", type=Path, help="Use an already downloaded archive")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        raise SystemExit(f"Output directory must be empty: {output}")

    with tempfile.TemporaryDirectory(prefix="sumi-sensevoice-") as temporary:
        temporary_root = Path(temporary)
        archive = args.archive.resolve() if args.archive else temporary_root / "upstream.tar.bz2"
        if not args.archive:
            print("Downloading pinned official SenseVoice INT8 release...")
            urllib.request.urlretrieve(args.upstream_url, archive)
        if not archive.is_file():
            raise SystemExit(f"Missing archive: {archive}")

        extract_root = temporary_root / "extract"
        with tarfile.open(archive, "r:bz2") as bundle:
            members = bundle.getmembers()
            if any(member.name.startswith("/") or ".." in Path(member.name).parts for member in members):
                raise SystemExit("Unsafe archive path")
            bundle.extractall(extract_root, members=members, filter="data")

        output.mkdir(parents=True, exist_ok=True)
        for name in REQUIRED:
            shutil.copy2(find_required(extract_root, name), output / name)
        if (output / "model.int8.onnx").stat().st_size < 50 * 1024 * 1024:
            raise SystemExit("SenseVoice model is unexpectedly small")
        if (output / "tokens.txt").stat().st_size < 10 * 1024:
            raise SystemExit("SenseVoice token file is unexpectedly small")

        manifest = {
            "id": REPOSITORY_ID,
            "version": args.version,
            "runtime": "sherpa-onnx-sensevoice",
            "source": {
                "provider": "k2-fsa/sherpa-onnx",
                "version": UPSTREAM_VERSION,
                "url": args.upstream_url,
                "archiveSha256": sha256(archive),
            },
            "languages": ["zh", "en", "ja", "ko", "yue"],
            "quantization": "int8",
            "createdAt": datetime.now(UTC).replace(microsecond=0).isoformat(),
            "files": package_files(output),
        }
        (output / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"Built {output}")
        print(f"Package size: {sum(item['sizeBytes'] for item in manifest['files']) / 1024 / 1024:.1f} MB")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
