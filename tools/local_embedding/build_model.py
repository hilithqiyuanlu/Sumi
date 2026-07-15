#!/usr/bin/env python3
"""Build Sumi's signed local embedding package from an immutable BGE revision.

This script is intentionally not run as part of Flutter builds. It produces a
portable package only after an explicit source revision is supplied, so a
published package always identifies the exact upstream checkpoint it used.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from datetime import UTC, datetime
from pathlib import Path


MODEL_ID = "BAAI/bge-small-zh-v1.5"
PACKAGE_ID = "Hilith/bge-small-zh-v1.5-onnx-int8"
VECTOR_DIMENSIONS = 512
MAX_LENGTH = 512


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
        for file in sorted(root.rglob("*"))
        if file.is_file() and file.name != "manifest.json"
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version", required=True, help="Sumi package version, e.g. 1.0.0")
    parser.add_argument(
        "--source-revision",
        required=True,
        help="Immutable upstream commit hash for BAAI/bge-small-zh-v1.5",
    )
    parser.add_argument(
        "--source",
        choices=("modelscope", "huggingface"),
        default="modelscope",
        help="Checkpoint mirror used for the one-time build",
    )
    return parser.parse_args()


def download_checkpoint(source: str, revision: str, target: Path) -> Path:
    if source == "modelscope":
        from modelscope import snapshot_download

        location = snapshot_download(MODEL_ID, revision=revision, cache_dir=str(target))
        return Path(location)

    from huggingface_hub import snapshot_download

    location = snapshot_download(MODEL_ID, revision=revision, cache_dir=str(target))
    return Path(location)


def main() -> int:
    args = parse_args()
    if args.output.exists() and any(args.output.iterdir()):
        raise SystemExit(f"Output directory must be empty: {args.output}")

    try:
        import torch
        from onnxruntime.quantization import QuantType, quantize_dynamic
        from transformers import AutoModel, AutoTokenizer
    except ImportError as error:
        raise SystemExit(
            "Install tool dependencies first: pip install -r tools/local_embedding/requirements.txt"
        ) from error

    staging = args.output.parent / f".{args.output.name}.staging"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    try:
        checkpoint = download_checkpoint(args.source, args.source_revision, staging / "cache")
        tokenizer = AutoTokenizer.from_pretrained(checkpoint, local_files_only=True)
        model = AutoModel.from_pretrained(checkpoint, local_files_only=True)
        model.eval()

        class MeanPoolingEmbedding(torch.nn.Module):
            def __init__(self, encoder: object) -> None:
                super().__init__()
                self.encoder = encoder

            def forward(self, input_ids, attention_mask, token_type_ids):
                output = self.encoder(
                    input_ids=input_ids,
                    attention_mask=attention_mask,
                    token_type_ids=token_type_ids,
                ).last_hidden_state
                weights = attention_mask.unsqueeze(-1).to(output.dtype)
                pooled = (output * weights).sum(1) / weights.sum(1).clamp(min=1e-9)
                return torch.nn.functional.normalize(pooled, p=2, dim=1)

        wrapper = MeanPoolingEmbedding(model)
        sample = tokenizer(
            "Sumi 本地检索导出样例", max_length=MAX_LENGTH, truncation=True,
            padding="max_length", return_tensors="pt",
        )
        model_path = staging / "model.fp32.onnx"
        torch.onnx.export(
            wrapper,
            (sample["input_ids"], sample["attention_mask"], sample["token_type_ids"]),
            model_path,
            input_names=["input_ids", "attention_mask", "token_type_ids"],
            output_names=["sentence_embedding"],
            dynamic_axes={
                "input_ids": {0: "batch", 1: "sequence"},
                "attention_mask": {0: "batch", 1: "sequence"},
                "token_type_ids": {0: "batch", 1: "sequence"},
                "sentence_embedding": {0: "batch"},
            },
            opset_version=17,
        )

        package_root = staging / "package"
        tokenizer.save_pretrained(package_root / "tokenizer")
        quantize_dynamic(
            str(model_path), str(package_root / "model.onnx"), weight_type=QuantType.QInt8
        )
        manifest = {
            "id": PACKAGE_ID,
            "version": args.version,
            "architectureVersion": "sumi-bge-wordpiece-1",
            "embeddingVersion": f"{PACKAGE_ID}@{args.version}",
            "source": {"model": MODEL_ID, "revision": args.source_revision, "mirror": args.source},
            "architecture": {
                "format": "onnx",
                "opset": 17,
                "quantization": "dynamic-int8",
                "inputNames": ["input_ids", "attention_mask", "token_type_ids"],
                "outputName": "sentence_embedding",
                "pooling": "attention-mask-mean",
                "normalization": "l2",
                "vectorDimensions": VECTOR_DIMENSIONS,
                "maxLength": MAX_LENGTH,
            },
            "tokenizer": {
                "format": "huggingface-wordpiece",
                "version": "1",
                "directory": "tokenizer",
            },
            "license": "MIT",
            "createdAt": datetime.now(UTC).replace(microsecond=0).isoformat(),
            "files": package_files(package_root),
        }
        (package_root / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

        args.output.parent.mkdir(parents=True, exist_ok=True)
        if args.output.exists():
            args.output.rmdir()
        shutil.move(str(package_root), args.output)
        print(f"Built {args.output}")
        return 0
    finally:
        shutil.rmtree(staging, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
