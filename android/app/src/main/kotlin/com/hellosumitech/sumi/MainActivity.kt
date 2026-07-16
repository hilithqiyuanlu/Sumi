package com.hellosumitech.sumi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    private val embeddingEngine = EmbeddingEngine()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hellosumitech.sumi/embedding")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkDevice" -> {
                        val stat = StatFs(filesDir.absolutePath)
                        result.success(mapOf("isSupported" to true, "freeBytes" to stat.availableBytes))
                    }
                    "loadModel" -> try {
                        val modelPath = call.argument<String>("modelPath") ?: error("缺少 modelPath")
                        val tokenizerPath = call.argument<String>("tokenizerPath") ?: error("缺少 tokenizerPath")
                        val outputName = call.argument<String>("outputName") ?: error("缺少 outputName")
                        val inputNames = call.argument<List<String>>("inputNames")?.toSet() ?: error("缺少 inputNames")
                        val maxLength = call.argument<Int>("maxLength") ?: error("缺少 maxLength")
                        embeddingEngine.load(modelPath, tokenizerPath, outputName, inputNames, maxLength)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("model_load_failed", error.message, null)
                    }
                    "embed" -> try {
                        val texts = call.argument<List<String>>("texts") ?: emptyList()
                        result.success(embeddingEngine.embed(texts))
                    } catch (error: Exception) {
                        result.error("embedding_failed", error.message, null)
                    }
                    "unload" -> { embeddingEngine.unload(); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hellosumitech.sumi/app_update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "install" -> try {
                        val apkPath = call.argument<String>("apkPath") ?: error("缺少 apkPath")
                        val apk = File(apkPath)
                        require(apk.exists() && apk.isFile) { "更新安装包不存在" }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName"),
                                ),
                            )
                            result.success("permission_required")
                        } else {
                            val uri = FileProvider.getUriForFile(
                                this,
                                "$packageName.updateprovider",
                                apk,
                            )
                            startActivity(
                                Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                },
                            )
                            result.success("installer_opened")
                        }
                    } catch (error: Exception) {
                        result.error("update_install_failed", error.message, null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
