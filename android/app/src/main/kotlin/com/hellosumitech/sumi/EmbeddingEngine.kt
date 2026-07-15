package com.hellosumitech.sumi

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.File
import java.nio.LongBuffer
import kotlin.math.sqrt

/**
 * Local-only BGE encoder for Sumi's verified ONNX package. The package must
 * expose standard BERT inputs and a 512-wide sentence/last-hidden-state output.
 */
class EmbeddingEngine {
    private val environment = OrtEnvironment.getEnvironment()
    private var session: OrtSession? = null
    private var tokenizer: WordPieceTokenizer? = null
    private var outputName: String? = null
    private var inputNames: Set<String> = emptySet()

    fun load(
        modelPath: String,
        tokenizerPath: String,
        outputName: String,
        inputNames: Set<String>,
        maxLength: Int,
    ) {
        unload()
        val created = environment.createSession(modelPath, OrtSession.SessionOptions())
        require(created.outputNames.contains(outputName)) { "模型缺少声明的句向量输出" }
        require(inputNames.contains("input_ids") && inputNames.contains("attention_mask")) { "模型清单输入不完整" }
        require(created.inputNames.containsAll(inputNames)) { "模型输入与清单不一致" }
        session = created
        require(maxLength in 2..512) { "模型最大长度无效" }
        tokenizer = WordPieceTokenizer(File(tokenizerPath), maxLength)
        this.outputName = outputName
        this.inputNames = inputNames
    }

    fun embed(texts: List<String>): List<List<Float>> {
        val activeSession = requireNotNull(session) { "本地模型尚未加载" }
        val activeTokenizer = requireNotNull(tokenizer) { "本地词表尚未加载" }
        return texts.map { text ->
            val encoded = activeTokenizer.encode(text)
            val shape = longArrayOf(1, encoded.inputIds.size.toLong())
            val tensors = mutableListOf<OnnxTensor>()
            try {
                val inputs = linkedMapOf<String, OnnxTensor>()
                fun add(name: String, values: LongArray) {
                    if (inputNames.contains(name)) {
                        val tensor = OnnxTensor.createTensor(environment, LongBuffer.wrap(values), shape)
                        tensors.add(tensor)
                        inputs[name] = tensor
                    }
                }
                add("input_ids", encoded.inputIds)
                add("attention_mask", encoded.attentionMask)
                add("token_type_ids", LongArray(encoded.inputIds.size))
                if (inputs.isEmpty()) error("模型输入不兼容")
                activeSession.run(inputs).use { output ->
                    val tensor = output[outputName] as? OnnxTensor
                        ?: error("模型输出不兼容")
                    val values = tensor.floatBuffer
                    val vector = FloatArray(512)
                    values.get(vector)
                    require(values.remaining() == 0) { "模型句向量维度不兼容" }
                    normalize(vector).toList()
                }
            } finally {
                tensors.forEach { it.close() }
            }
        }
    }

    fun unload() {
        session?.close()
        session = null
        tokenizer = null
        outputName = null
        inputNames = emptySet()
    }

    private fun normalize(values: FloatArray): FloatArray {
        var squared = 0.0
        values.forEach { squared += it * it }
        val norm = sqrt(squared).toFloat().coerceAtLeast(1e-12f)
        return FloatArray(values.size) { index -> values[index] / norm }
    }
}

private data class EncodedText(val inputIds: LongArray, val attentionMask: LongArray)

private class WordPieceTokenizer(vocabFile: File, private val maxLength: Int) {
    private val vocab = vocabFile.readLines().mapIndexed { index, token -> token to index.toLong() }.toMap()
    private val cls = vocab["[CLS]"] ?: error("词表缺少 [CLS]")
    private val sep = vocab["[SEP]"] ?: error("词表缺少 [SEP]")
    private val unk = vocab["[UNK]"] ?: error("词表缺少 [UNK]")
    fun encode(text: String): EncodedText {
        val pieces = mutableListOf<Long>(cls)
        basicTokens(text).forEach { token -> pieces.addAll(wordPieces(token)) }
        if (pieces.size >= maxLength) pieces.subList(maxLength - 1, pieces.size).clear()
        pieces.add(sep)
        return EncodedText(pieces.toLongArray(), LongArray(pieces.size) { 1L })
    }

    private fun basicTokens(text: String): List<String> {
        val values = mutableListOf<String>()
        val current = StringBuilder()
        fun flush() { if (current.isNotEmpty()) { values.add(current.toString()); current.clear() } }
        text.lowercase().forEach { char ->
            when {
                char.isWhitespace() -> flush()
                isChinese(char) || isPunctuation(char) -> { flush(); values.add(char.toString()) }
                else -> current.append(char)
            }
        }
        flush()
        return values
    }

    private fun wordPieces(token: String): List<Long> {
        if (vocab.containsKey(token)) return listOf(vocab.getValue(token))
        val result = mutableListOf<Long>()
        var start = 0
        while (start < token.length) {
            var end = token.length
            var found: Long? = null
            while (start < end) {
                val piece = (if (start == 0) "" else "##") + token.substring(start, end)
                val id = vocab[piece]
                if (id != null) { found = id; break }
                end--
            }
            if (found == null) return listOf(unk)
            result.add(found)
            start = end
        }
        return result
    }

    private fun isChinese(value: Char) = value.code in 0x4E00..0x9FFF
    private fun isPunctuation(value: Char) = !value.isLetterOrDigit() && !value.isWhitespace()
}
