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

  const MemoryExtractionDecision({
    required this.action,
    this.type = MemoryType.explicit,
    this.category,
    this.content,
    this.quotedText,
    this.replacesId,
  });

  Map<String, Object?> toJson() => {
    'action': action.name,
    'type': type.name,
    if (category != null) 'category': category,
    if (content != null) 'content': content,
    if (quotedText != null) 'quotedText': quotedText,
    if (replacesId != null) 'replacesId': replacesId,
  };
}

class MemoryExtractionCandidate {
  final String id;
  final MemoryType type;
  final String category;
  final String content;
  final String? projectId;

  const MemoryExtractionCandidate({
    required this.id,
    this.type = MemoryType.explicit,
    required this.category,
    required this.content,
    this.projectId,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.name,
    'category': category,
    'content': content,
    if (projectId != null) 'projectId': projectId,
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
  final String? Function() currentProjectId;
  Future<void> _queue = Future<void>.value();

  MemoryExtractionService({
    required this.memory,
    required this.capability,
    required this.onMemoryChanged,
    required this.currentProjectId,
  });

  Future<void> process({required String messageId, required String message}) {
    _queue = _queue.then(
      (_) => _process(messageId: messageId, message: message),
    );
    return _queue;
  }

  Future<void> _process({
    required String messageId,
    required String message,
  }) async {
    try {
      if (!await memory.claimExtraction(messageId)) return;
      final projectId = currentProjectId();
      final candidates = await memory.extractionCandidates(
        projectId: projectId,
        limit: 6,
      );
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
        currentProjectId: projectId,
      );
      if (!applied) return;
      if (decision.action != MemoryExtractionAction.ignore) {
        await memory.exportUserModel();
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
}
