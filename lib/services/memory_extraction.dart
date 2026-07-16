import 'dart:async';

import 'memory_service.dart';

enum MemoryExtractionAction { ignore, save, replace }

class MemoryExtractionDecision {
  final MemoryExtractionAction action;
  final MemoryType type;
  final String? category;
  final String? content;
  final String? quotedText;
  final String? replacesId;
  final double confidence;

  const MemoryExtractionDecision({
    required this.action,
    this.type = MemoryType.explicit,
    this.category,
    this.content,
    this.quotedText,
    this.replacesId,
    this.confidence = 1,
  });

  Map<String, Object?> toJson() => {
    'action': action.name,
    'type': type.name,
    if (category != null) 'category': category,
    if (content != null) 'content': content,
    if (quotedText != null) 'quotedText': quotedText,
    if (replacesId != null) 'replacesId': replacesId,
    'confidence': confidence,
  };
}

class MemoryExtractionCandidate {
  final String id;
  final MemoryType type;
  final String category;
  final String content;

  const MemoryExtractionCandidate({
    required this.id,
    this.type = MemoryType.explicit,
    required this.category,
    required this.content,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'category': category,
    'content': content,
  };
}

abstract interface class MemoryExtractionCapability {
  Future<MemoryExtractionDecision?> extractMemory({
    required String message,
    required List<MemoryExtractionCandidate> candidates,
  });
}

/// Runs after a user message has been persisted. It deliberately has no chat
/// state: extraction must not affect the reply stream or inspect its output.
class MemoryExtractionService {
  final MemoryService memory;
  final MemoryExtractionCapability capability;
  final void Function() onMemoryChanged;
  final void Function(String messageId) onMemorySaved;
  Future<void> _queue = Future<void>.value();

  MemoryExtractionService({
    required this.memory,
    required this.capability,
    required this.onMemoryChanged,
    required this.onMemorySaved,
  });

  Future<void> process({
    required String messageId,
    required String message,
    String source = 'chat',
    bool retry = false,
  }) {
    _queue = _queue.then(
      (_) => _process(
        messageId: messageId,
        message: message,
        source: source,
        retry: retry,
      ),
    );
    return _queue;
  }

  Future<void> _process({
    required String messageId,
    required String message,
    required String source,
    required bool retry,
  }) async {
    try {
      final claimed = retry
          ? await memory.reclaimExtraction(messageId)
          : await memory.claimExtraction(messageId, source: source);
      if (!claimed) return;
      final candidates = await memory.extractionCandidates(limit: 6);
      final decision = await capability.extractMemory(
        message: message,
        candidates: candidates,
      );
      if (decision == null) {
        await memory.finishExtraction(
          messageId,
          status: 'failed',
          errorCategory: 'no_valid_decision',
        );
        return;
      }
      final applied = await memory.applyExtractionDecision(
        messageId: messageId,
        userMessage: message,
        decision: decision,
        candidateReplaceIds: candidates.map((item) => item.id).toSet(),
      );
      if (!applied) return;
      if (decision.action != MemoryExtractionAction.ignore) {
        await memory.exportUserModel();
        if (!await memory.hasUserMessageEvidence(messageId)) return;
        onMemorySaved(messageId);
        onMemoryChanged();
      }
    } catch (_) {
      // Background extraction is intentionally silent and must not affect chat.
      try {
        await memory.finishExtraction(
          messageId,
          status: 'failed',
          errorCategory: 'runtime',
        );
      } catch (_) {
        // The app may have been closed while this best-effort task was running.
      }
    }
  }

  Future<void> retryRecoverable(
    Future<String?> Function(String messageId) messageForId,
  ) async {
    for (final messageId in await memory.retryableExtractionIds()) {
      final message = await messageForId(messageId);
      if (message == null || message.trim().isEmpty) continue;
      await process(messageId: messageId, message: message, retry: true);
    }
  }
}
