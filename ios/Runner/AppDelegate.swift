import Flutter
import UIKit
import Foundation
import onnxruntime_objc

private final class EmbeddingBridge {
  private let environment: ORTEnv
  private var session: ORTSession?
  private var vocabulary: [String: NSNumber] = [:]
  private var outputName = ""
  private var inputNames: Set<String> = []
  private var maxLength = 512

  init() {
    environment = try! ORTEnv(loggingLevel: ORTLoggingLevel.warning)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "checkDevice":
      let free = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? NSNumber
      result([
        "isSupported": true,
        "freeBytes": free?.int64Value ?? 0,
      ])
    case "loadModel":
      do {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String,
              let tokenizerPath = args["tokenizerPath"] as? String,
              let outputName = args["outputName"] as? String,
              let inputNames = args["inputNames"] as? [String],
              let maxLength = args["maxLength"] as? Int,
              maxLength >= 2 && maxLength <= 512 else {
          throw NSError(domain: "SumiEmbedding", code: 1, userInfo: [NSLocalizedDescriptionKey: "模型参数不完整"])
        }
        let options = try ORTSessionOptions()
        let created = try ORTSession(env: environment, modelPath: modelPath, sessionOptions: options)
        let availableInputs = try created.inputNames()
        let availableOutputs = try created.outputNames()
        guard availableOutputs.contains(outputName), inputNames.contains("input_ids"), inputNames.contains("attention_mask"), Set(inputNames).isSubset(of: Set(availableInputs)) else {
          throw NSError(domain: "SumiEmbedding", code: 2, userInfo: [NSLocalizedDescriptionKey: "模型清单与运行时不兼容"])
        }
        self.vocabulary = try Self.loadVocabulary(tokenizerPath)
        self.session = created
        self.outputName = outputName
        self.inputNames = Set(inputNames)
        self.maxLength = maxLength
        result(nil)
      } catch {
        result(FlutterError(code: "model_load_failed", message: error.localizedDescription, details: nil))
      }
    case "embed":
      do {
        guard let args = call.arguments as? [String: Any], let texts = args["texts"] as? [String] else {
          throw NSError(domain: "SumiEmbedding", code: 3, userInfo: [NSLocalizedDescriptionKey: "缺少文本"])
        }
        result(try texts.map(embed))
      } catch {
        result(FlutterError(code: "embedding_failed", message: error.localizedDescription, details: nil))
      }
    case "unload":
      session = nil
      vocabulary = [:]
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func embed(_ text: String) throws -> [Float] {
    guard let session else { throw NSError(domain: "SumiEmbedding", code: 4, userInfo: [NSLocalizedDescriptionKey: "本地模型尚未加载"]) }
    let ids = try tokenize(text)
    let shape: [NSNumber] = [1, NSNumber(value: ids.count)]
    let input = try tensor(ids, shape: shape)
    let mask = try tensor(Array(repeating: Int64(1), count: ids.count), shape: shape)
    var inputs: [String: ORTValue] = ["input_ids": input, "attention_mask": mask]
    if inputNames.contains("token_type_ids") {
      inputs["token_type_ids"] = try tensor(Array(repeating: Int64(0), count: ids.count), shape: shape)
    }
    let output = try session.run(withInputs: inputs, outputNames: [outputName], runOptions: nil)
    guard let value = output[outputName] else {
      throw NSError(domain: "SumiEmbedding", code: 5, userInfo: [NSLocalizedDescriptionKey: "模型输出不是 512 维句向量"])
    }
    let data = try value.tensorData()
    guard data.count == 512 * MemoryLayout<Float>.size else {
      throw NSError(domain: "SumiEmbedding", code: 5, userInfo: [NSLocalizedDescriptionKey: "模型输出不是 512 维句向量"])
    }
    let immutableData = data as Data
    var vector = immutableData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    let norm = sqrt(vector.reduce(0) { $0 + Double($1 * $1) })
    guard norm > 0 else { throw NSError(domain: "SumiEmbedding", code: 6, userInfo: [NSLocalizedDescriptionKey: "模型输出无效"]) }
    vector = vector.map { $0 / Float(norm) }
    return vector
  }

  private func tokenize(_ text: String) throws -> [Int64] {
    guard let cls = vocabulary["[CLS]"], let sep = vocabulary["[SEP]"], let unk = vocabulary["[UNK]"] else { throw NSError(domain: "SumiEmbedding", code: 7, userInfo: [NSLocalizedDescriptionKey: "词表缺少特殊符号"]) }
    var result = [cls.int64Value]
    for token in basicTokens(text) {
      result.append(contentsOf: wordPieces(token, unknown: unk.int64Value))
      if result.count >= maxLength - 1 {
        result = Array(result.prefix(maxLength - 1))
        break
      }
    }
    result.append(sep.int64Value)
    return result
  }

  private func tensor(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
    let data = values.withUnsafeBufferPointer { buffer -> NSMutableData in
      NSMutableData(bytes: buffer.baseAddress!, length: buffer.count * MemoryLayout<Int64>.size)
    }
    return try ORTValue(tensorData: data, elementType: ORTTensorElementDataType.int64, shape: shape)
  }

  private func basicTokens(_ text: String) -> [String] {
    var values: [String] = []
    var current = ""
    func flush() {
      if !current.isEmpty { values.append(current); current = "" }
    }
    for character in text.lowercased() {
      if character.isWhitespace {
        flush()
      } else if isChinese(character) || (!character.isLetter && !character.isNumber) {
        flush()
        values.append(String(character))
      } else {
        current.append(character)
      }
    }
    flush()
    return values
  }

  private func wordPieces(_ token: String, unknown: Int64) -> [Int64] {
    if let id = vocabulary[token] { return [id.int64Value] }
    let characters = Array(token)
    var start = 0
    var values: [Int64] = []
    while start < characters.count {
      var end = characters.count
      var found: NSNumber?
      while start < end {
        let piece = (start == 0 ? "" : "##") + String(characters[start..<end])
        if let id = vocabulary[piece] { found = id; break }
        end -= 1
      }
      guard let id = found else { return [unknown] }
      values.append(id.int64Value)
      start = end
    }
    return values
  }

  private func isChinese(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains(Int($0.value)) }
  }

  private static func loadVocabulary(_ path: String) throws -> [String: NSNumber] {
    let lines = try String(contentsOfFile: path, encoding: .utf8).components(separatedBy: .newlines)
    return Dictionary(uniqueKeysWithValues: lines.enumerated().filter { !$0.element.isEmpty }.map { ($0.element, NSNumber(value: $0.offset)) })
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let embeddingBridge = EmbeddingBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.hellosumitech.sumi/embedding",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler(embeddingBridge.handle)
  }
}
