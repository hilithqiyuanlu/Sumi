import 'dart:async';

import 'memory_service.dart';

enum MemoryExtractionAction { ignore, save, replace }

class MemoryExtractionDecision {
  final MemoryExtractionAction action;
  final String? category;
  final String? content;
  final String? quotedText;
  final String? replacesId;

  const MemoryExtractionDecision({
    required this.action,
    this.category,
    this.content,
    this.quotedText,
    this.replacesId,
  });

  Map<String, Object?> toJson() => {
    'action': action.name,
    if (category != null) 'category': category,
    if (content != null) 'content': content,
    if (quotedText != null) 'quotedText': quotedText,
    if (replacesId != null) 'replacesId': replacesId,
  };
}

class MemoryExtractionCandidate {
  final String id;
  final String category;
  final String content;

  const MemoryExtractionCandidate({
    required this.id,
    required this.category,
    required this.content,
  });

  Map<String, Object?> toJson() => {
    'id': id,
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

  MemoryExtractionService({
    required this.memory,
    required this.capability,
    required this.onMemoryChanged,
  });

  Future<void> process({
    required String messageId,
    required String message,
  }) async {
    try {
      if (!await memory.claimExtraction(messageId)) return;
      final candidates = await memory.explicitCandidates(limit: 3);
      final decision = await capability.extractMemory(
        message: message,
        candidates: candidates,
      );
      if (decision == null) {
        await memory.finishExtraction(messageId, status: 'failed');
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
        onMemoryChanged();
      }
    } catch (_) {
      // Background extraction is intentionally silent and must not affect chat.
      try {
        await memory.finishExtraction(messageId, status: 'failed');
      } catch (_) {
        // The app may have been closed while this best-effort task was running.
      }
    }
  }
}
