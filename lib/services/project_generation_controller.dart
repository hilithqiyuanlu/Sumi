import 'package:flutter/foundation.dart';

import 'project_generation.dart';

class ProjectGenerationController extends ChangeNotifier {
  final Map<String, ProjectGenerationSession> _chatSessions = {};

  ProjectGenerationSession? forToolCall(String toolCallId) =>
      _chatSessions[toolCallId];

  void add(ProjectGenerationSession session) {
    final toolCallId = session.toolCallId;
    if (toolCallId == null) return;
    _chatSessions[toolCallId] = session;
    session.addListener(notifyListeners);
    notifyListeners();
  }

  ProjectGenerationSession? takePendingNavigation() {
    for (final session in _chatSessions.values) {
      if (session.takeNavigation()) return session;
    }
    return null;
  }

  @override
  void dispose() {
    for (final session in _chatSessions.values) {
      session.removeListener(notifyListeners);
      session.disposeSession();
    }
    _chatSessions.clear();
    super.dispose();
  }
}
