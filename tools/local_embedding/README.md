# Local Embedding Release Tools

These scripts build and verify the only package the Sumi app will accept. They
are release tooling, not part of the Flutter build and never include a model in
Git.

Install the pinned tooling in a dedicated virtual environment:

```sh
python3 -m venv .venv-local-embedding
.venv-local-embedding/bin/pip install -r tools/local_embedding/requirements.txt
```

Build from an **immutable** revision of `BAAI/bge-small-zh-v1.5`. ModelScope is
the default mirror. The revision must be a commit hash obtained from the source
repository; do not use `main` or `master` for a release.

```sh
.venv-local-embedding/bin/python tools/local_embedding/build_model.py \
  --output /tmp/sumi-bge-1.0.0 \
  --version 1.0.0 \
  --source-revision <immutable-commit-hash>
```

The output contains `model.onnx`, the complete `tokenizer/` directory, and a
manifest with every file size and SHA-256. The ONNX graph returns one 512-value,
mean-pooled and L2-normalized `sentence_embedding` per input.

Validate before every release. It verifies manifest integrity, ONNX metadata,
Chinese/English related-vs-unrelated pairs, dimensions, normalization, and can
write package reference vectors for native bridge parity checks.

```sh
.venv-local-embedding/bin/python tools/local_embedding/validate_package.py \
  /tmp/sumi-bge-1.0.0 --write-golden /tmp/sumi-bge-golden.json
```

Android and iOS bridge tests must export the same fixture keys into JSON before
release. Compare them with the package reference; cosine similarity must be at
least `0.999` for every fixture.

```sh
.venv-local-embedding/bin/python tools/local_embedding/validate_package.py \
  /tmp/sumi-bge-1.0.0 \
  --compare-platform-results android-vectors.json ios-vectors.json
```

ModelScope publication defaults to a dry run. It validates the package first,
does not read a token without `--publish`, and requires the repository and
release revision explicitly. `--publish` reads only `MODELSCOPE_API_TOKEN`.

```sh
python3 tools/local_embedding/publish_modelscope.py /tmp/sumi-bge-1.0.0 \
  --repo Hilith/bge-small-zh-v1.5-onnx-int8 --revision v1.0.0

MODELSCOPE_API_TOKEN=... python3 tools/local_embedding/publish_modelscope.py \
  /tmp/sumi-bge-1.0.0 --repo Hilith/bge-small-zh-v1.5-onnx-int8 \
  --revision v1.0.0 --publish
```
