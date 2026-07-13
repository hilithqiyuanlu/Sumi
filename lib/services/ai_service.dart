import 'dart:convert';

import 'package:http/http.dart' as http;

/// SplitResult —— AI 拆分判断结果。
class SplitResult {
  final bool split;
  final List<String> items;

  const SplitResult({required this.split, required this.items});

  factory SplitResult.fromJson(Map<String, Object?> json) {
    final items = (json['items'] as List<Object?>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    return SplitResult(
      split: (json['split'] as bool?) ?? false,
      items: items,
    );
  }

  /// 单条结果（无需拆分）。
  factory SplitResult.single(String text) =>
      SplitResult(split: false, items: [text]);
}

// ---------------------------------------------------------------------------
// AiService
// ---------------------------------------------------------------------------

/// DeepSeek API 调用服务。
class AiService {
  static const _baseUrl = 'https://api.deepseek.com/v1/chat/completions';
  static const _model = 'deepseek-chat';

  static const _systemPrompt = '你是 Sumi（米糖），一个自学个人助手的 AI 引擎。\n'
      '你的任务是将用户输入的长文本智能拆分为独立可执行的 todo 事项。\n'
      '\n'
      '规则：\n'
      '1. 如果文本描述的是单一事项（尽管很长），不要拆分。\n'
      '2. 如果包含多个独立步骤或事项，拆分为独立 todo。\n'
      '3. 每条 todo 保留完整的语义，可脱离上下文理解。\n'
      '4. 拆分后每条 2-20 字为宜。\n'
      '5. 以 JSON 格式回复，不要带任何额外文字。\n'
      '\n'
      '回复格式：\n'
      '{"split": true/false, "items": ["事项1", "事项2"]}';

  final String apiKey;
  final http.Client _client;

  AiService({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client();

  /// Todo 拆分判断。
  /// 返回 null = 调用失败，调用方应降级为直接创建。
  Future<SplitResult?> splitTodo(String text) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': text},
              ],
              'response_format': {'type': 'json_object'},
              'max_tokens': 500,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>)['message']
          as Map<String, Object?>?;
      if (message == null) return null;

      final content = message['content'] as String?;
      if (content == null) return null;

      final result = jsonDecode(content) as Map<String, Object?>;
      return SplitResult.fromJson(result);
    } catch (_) {
      return null;
    }
  }

  /// 润色 todo 标题 —— 调用 AI 优化表达，返回润色后文本。
  /// 返回 null = 调用失败。
  Future<String?> polishTodo(String text) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      '你是 Sumi（米糖），一个个人助手。你的任务是优化用户提供的 todo 标题。\n'
                          '要求：凝练清晰、保留原意、2-20 字、只返回优化后的文本，不要加引号或额外文字。',
                },
                {'role': 'user', 'content': text},
              ],
              'max_tokens': 100,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>)['message']
          as Map<String, Object?>?;
      if (message == null) return null;

      final content = message['content'] as String?;
      return content?.trim();
    } catch (_) {
      return null;
    }
  }

  /// Streaming 对话 —— 返回逐 chunk 的 delta content。
  /// 用于需要流式输出的场景（如后续米糖 Tab）。
  Stream<String> streamChat(String prompt) async* {
    try {
      final request = http.Request('POST', Uri.parse(_baseUrl));
      request.headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      });
      request.body = jsonEncode({
        'model': _model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'max_tokens': 1000,
      });

      final streamedResponse =
          await _client.send(request).timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) return;

      await for (final chunk in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final trimmed = chunk.trim();
        if (!trimmed.startsWith('data: ')) continue;

        final data = trimmed.substring(6);
        if (data == '[DONE]') return;

        try {
          final json = jsonDecode(data) as Map<String, Object?>;
          final choices = json['choices'] as List<Object?>?;
          if (choices == null || choices.isEmpty) continue;

          final delta = (choices.first as Map<String, Object?>?)?['delta']
              as Map<String, Object?>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // 跳过无法解析的 chunk
        }
      }
    } catch (_) {
      // stream 异常时静默结束
    }
  }

  /// 预留：通用对话。
  Future<String?> chat(String prompt) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _model,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'max_tokens': 1000,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, Object?>;
      final choices = body['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) return null;

      final message = (choices.first as Map<String, Object?>)['message']
          as Map<String, Object?>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}
