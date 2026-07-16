# 本地高质量语音识别模型包

Sumi 仅下载 ModelScope 仓库 `Hilith/sumi-sensevoice-small-onnx-int8` 的固定模型包。语音文件和识别结果始终留在手机本机，不上传到 Sumi 服务。

模型包必须包含：

```text
model.int8.onnx
tokens.txt
manifest.json
```

`manifest.json` 中的仓库 ID 必须为 `Hilith/sumi-sensevoice-small-onnx-int8`，并列出每个文件的大小和 SHA-256。客户端先下载到临时目录、校验文件、加载识别器，全部成功后才替换旧模型。因此 App 更新、下载中断或新包损坏都不会破坏已安装模型。

模型二进制不进入 APK 或 IPA。用户在“本地智能”下载一次后，模型保存在 App 私有目录；正常应用更新会保留它，只有卸载 App、清除应用数据或主动删除模型才会移除。

当前 `v1.0.0` 的实际下载量约为 226MB（INT8 ONNX + 词表），支持中文、英文、粤语、日语和韩语识别。

发布工具在 [`tools/local_speech`](../tools/local_speech/README.md)。
