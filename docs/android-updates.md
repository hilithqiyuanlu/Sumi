# Android 测试版发布

Sumi 的 Android 更新只使用当前 GitHub 仓库，不需要网站。手机读取仓库中的 `release/update.json`，APK 由 GitHub Release 托管。

## 一次性配置

在 GitHub 仓库的 `Settings -> Secrets and variables -> Actions` 新建四个 Repository secrets：

- `ANDROID_KEYSTORE_BASE64`：本机发布 `.jks` 文件经 `base64` 编码后的完整内容。
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

这四项必须与 `android/key.properties` 当前指向的发布密钥一致。密钥文件和 `key.properties` 不上传到 GitHub。

仓库必须公开，且默认分支为 `main`。

## 每次发布

1. 把 `pubspec.yaml` 的 `version` 同时递增，例如 `1.0.0+1` 改为 `1.0.1+2`，并推送到 `main`。
2. 打开 GitHub 的 `Actions`，选择 `Publish Android update`，点击 `Run workflow`。
3. 工作流会创建 `v1.0.1` Release、上传 `app-arm64-v8a-release.apk` 并更新 `release/update.json`。
4. 同学在 Android App 的 `设置 -> 应用更新` 点击“检查更新”，下载后按 Android 系统提示安装。

首发包和后续更新都必须使用同一发布密钥。若手机先装了 Debug 签名包，需要先卸载它，再安装第一份正式签名的 Release 包；之后可以一直覆盖更新。

本地检索和本地生成模型在应用私有数据中。覆盖安装不会删除它们；卸载 App 或在设置中删除模型才会清除。
