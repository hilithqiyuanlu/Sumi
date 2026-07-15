#!/usr/bin/env python3
"""Offline acceptance checks for a Sumi local embedding package."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path


EXPECTED_DIMENSIONS = 512
FIXTURES = {
    "zh_anchor": "我今天复习了日语语法。",
    "zh_related": "今天我在学习日语的语法。",
    "zh_unrelated": "番茄炒蛋应该怎么做？",
    "en_anchor": "I reviewed Japanese grammar today.",
    "en_related": "Today I studied Japanese grammar.",
    "en_unrelated": "How do I cook tomato and eggs?",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cosine(first: list[float], second: list[float]) -> float:
    return sum(a * b for a, b in zip(first, second))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--write-golden", type=Path)
    parser.add_argument(
        "--compare-platform-results", nargs="*", type=Path,
        help="JSON files exported by Android/iOS bridges, keyed by fixture name",
    )
    args = parser.parse_args()
    root = args.package.resolve()
    manifest_path = root / "manifest.json"
    if not manifest_path.is_file():
        raise SystemExit("Missing manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    architecture = manifest.get("architecture", {})
    if architecture.get("vectorDimensions") != EXPECTED_DIMENSIONS:
        raise SystemExit("Expected a 512-dimensional embedding architecture")
    if architecture.get("outputName") != "sentence_embedding":
        raise SystemExit("Manifest must declare sentence_embedding as the output")
    if architecture.get("pooling") != "attention-mask-mean" or architecture.get("normalization") != "l2":
        raise SystemExit("Manifest must declare mean pooling and L2 normalization")
    for entry in manifest.get("files", []):
        path = root / entry["path"]
        if not path.is_file() or path.stat().st_size != entry["sizeBytes"] or sha256(path) != entry["sha256"]:
            raise SystemExit(f"Checksum or size mismatch: {entry['path']}")

    try:
        import numpy as np
        import onnxruntime as ort
        from transformers import AutoTokenizer
    except ImportError as error:
        raise SystemExit(
            "Install tool dependencies first: pip install -r tools/local_embedding/requirements.txt"
        ) from error

    tokenizer = AutoTokenizer.from_pretrained(root / "tokenizer", local_files_only=True)
    session = ort.InferenceSession(str(root / "model.onnx"), providers=["CPUExecutionProvider"])
    expected_inputs = architecture["inputNames"]
    actual_inputs = [item.name for item in session.get_inputs()]
    if actual_inputs != expected_inputs or session.get_outputs()[0].name != architecture["outputName"]:
        raise SystemExit("ONNX input/output metadata differs from manifest")

    def embed(text: str) -> list[float]:
        values = tokenizer(text, max_length=architecture["maxLength"], truncation=True,
                           return_tensors="np")
        feeds = {name: values[name].astype("int64") for name in expected_inputs}
        vector = session.run([architecture["outputName"]], feeds)[0][0].astype("float32")
        if len(vector) != EXPECTED_DIMENSIONS:
            raise SystemExit(f"Expected {EXPECTED_DIMENSIONS} dimensions, got {len(vector)}")
        norm = float(np.linalg.norm(vector))
        if not math.isclose(norm, 1.0, abs_tol=0.01):
            raise SystemExit(f"Expected L2-normalized output, got norm {norm}")
        return vector.tolist()

    vectors = {name: embed(text) for name, text in FIXTURES.items()}
    for language in ("zh", "en"):
        related = cosine(vectors[f"{language}_anchor"], vectors[f"{language}_related"])
        unrelated = cosine(vectors[f"{language}_anchor"], vectors[f"{language}_unrelated"])
        if related < unrelated + 0.05:
            raise SystemExit(
                f"{language} related pair is not sufficiently closer than unrelated pair: {related:.4f} vs {unrelated:.4f}"
            )
    if args.write_golden:
        args.write_golden.write_text(json.dumps({"fixtures": FIXTURES, "vectors": vectors}, ensure_ascii=False) + "\n", encoding="utf-8")
    for result_path in args.compare_platform_results or []:
        result = json.loads(result_path.read_text(encoding="utf-8"))
        platform_vectors = result.get("vectors", result)
        for name, expected in vectors.items():
            received = platform_vectors.get(name)
            if not isinstance(received, list) or len(received) != EXPECTED_DIMENSIONS:
                raise SystemExit(f"{result_path}: missing or invalid vector for {name}")
            if cosine(expected, received) < 0.999:
                raise SystemExit(f"{result_path}: {name} differs from the package reference")
    print("Package validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
