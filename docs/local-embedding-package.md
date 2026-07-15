# Sumi 本地 Embedding 模型包

客户端仅下载并加载 ModelScope 仓库 `Hilith/bge-small-zh-v1.5-onnx-int8` 的 `main` 版本。模型包不进入 App 安装包或 Git 仓库。

## 必需文件

```text
manifest.json
model.onnx
tokenizer/
```

`model.onnx` 必须基于 `BAAI/bge-small-zh-v1.5` 转换为 INT8 ONNX，接受标准 BERT 的 `input_ids`、`attention_mask`（可选 `token_type_ids`），输出已池化且 L2 归一化的 `[1, 512]` Float32 向量。不要发布未池化的 `[1, sequence, 512]` hidden state。

`manifest.json` 由 Sumi 发布流程生成。客户端只读取清单列出的文件，
不会假设 tokenizer 只有一个 `vocab.txt`：

```json
{
  "id": "Hilith/bge-small-zh-v1.5-onnx-int8",
  "version": "1.0.0",
  "architectureVersion": "sumi-bge-wordpiece-1",
  "embeddingVersion": "Hilith/bge-small-zh-v1.5-onnx-int8@1.0.0",
  "source": {"model": "BAAI/bge-small-zh-v1.5", "revision": "不可变提交哈希"},
  "architecture": {
    "format": "onnx",
    "quantization": "dynamic-int8",
    "inputNames": ["input_ids", "attention_mask", "token_type_ids"],
    "outputName": "sentence_embedding",
    "pooling": "attention-mask-mean",
    "normalization": "l2",
    "vectorDimensions": 512,
    "maxLength": 512
  },
  "tokenizer": {"format": "huggingface-wordpiece", "version": "1", "directory": "tokenizer"},
  "license": "MIT",
  "files": [
    {"path":"model.onnx","sizeBytes":12345678,"sha256":"64 位小写 SHA-256"},
    {"path":"tokenizer/vocab.txt","sizeBytes":123456,"sha256":"64 位小写 SHA-256"}
  ]
}
```

发布工具位于 [`tools/local_embedding`](../tools/local_embedding/README.md)。它要求
传入上游不可变提交哈希，导出池化、L2 归一化的 512 维 ONNX，再进行 INT8
量化和离线语义验收。发布命令默认 dry-run；只有显式传入 `--publish` 才会读取
`MODELSCOPE_API_TOKEN` 并上传。

发布前在 Android 与 iOS 真机验证：中文和英文短句均返回 512 维向量；相同输入稳定；相近句的余弦相似度高于无关句。客户端在文件大小或 SHA-256 任一不匹配时删除整个模型包。

## 当前发布门槛

当前仓库不包含模型二进制，也没有向 ModelScope 发布上述固定仓库。因此设置页会明确显示模型尚未可用，不会下载第三方或未校验的权重。正式发布前需完成 Android、iOS 的 ONNX Runtime 真机兼容验证，再将 iOS 运行时标记为可用。
