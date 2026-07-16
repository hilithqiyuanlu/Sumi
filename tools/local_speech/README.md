# Sumi 本地语音模型发布工具

本目录只生成并校验 Sumi 的 SenseVoice 手机模型包；模型二进制不进入 Git 或 App 安装包。

构建包：

```sh
python3 tools/local_speech/build_sensevoice_package.py \
  --output /tmp/sumi-sensevoice-1.0.0 --version 1.0.0
python3 tools/local_speech/validate_sensevoice_package.py /tmp/sumi-sensevoice-1.0.0
```

产物只有：

```text
model.int8.onnx
tokens.txt
manifest.json
```

发布默认只打印命令，不读取凭据：

```sh
python3 tools/local_speech/publish_modelscope.py /tmp/sumi-sensevoice-1.0.0 --revision v1.0.0
MODELSCOPE_API_TOKEN=... python3 tools/local_speech/publish_modelscope.py \
  /tmp/sumi-sensevoice-1.0.0 --revision v1.0.0 --publish
```

包来自 sherpa-onnx 固定的公开 SenseVoice INT8 版本，支持中文和英文混说。客户端会逐文件校验大小与 SHA-256，校验失败不会启用模型。
