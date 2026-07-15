package com.hellosumitech.sumi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.StatFs

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
    }
}
