import 'package:flutter/foundation.dart';

import '../models/models.dart';

class TimerController extends ChangeNotifier {
  final Map<String, StudyTimer> _timers = {};

  List<StudyTimer> get timers => List.unmodifiable(_timers.values);
  StudyTimer? byId(String id) => _timers[id];
  StudyTimer? byToolCallId(String id) {
    for (final timer in _timers.values) {
      if (timer.toolCallId == id) return timer;
    }
    return null;
  }

  void replaceAll(Iterable<StudyTimer> values) {
    _timers
      ..clear()
      ..addEntries(values.map((value) => MapEntry(value.id, value)));
    notifyListeners();
  }

  void put(StudyTimer timer) {
    _timers[timer.id] = timer;
    notifyListeners();
  }

  void remove(String id) {
    if (_timers.remove(id) != null) notifyListeners();
  }

  void tick() => notifyListeners();

  void clear() {
    if (_timers.isEmpty) return;
    _timers.clear();
    notifyListeners();
  }
}
