import 'dart:async';

import 'package:flutter/material.dart';

import 'features/home/home_page.dart';
import 'models/models.dart';
import 'store/sumi_store.dart';
import 'sumi_scope.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final store = await SumiStore.create();

      FlutterError.onError = (details) {
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      };

      runApp(SumiApp(store: store));
    },
    (error, stack) {
      debugPrint('Uncaught error: $error\n$stack');
    },
  );
}

class SumiApp extends StatefulWidget {
  final SumiStore store;
  const SumiApp({required this.store, super.key});

  @override
  State<SumiApp> createState() => _SumiAppState();
}

class _SumiAppState extends State<SumiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(widget.store.handleAppLifecycle(state));
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(widget.store.flushPersistence());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.store.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SumiScope(
      store: widget.store,
      child: MaterialApp(
        title: 'Sumi',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        builder: (context, child) => AnimatedBuilder(
          animation: widget.store.activeStudyTimerReminder,
          builder: (context, _) {
            final timer = widget.store.activeStudyTimerReminder.value;
            return Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (timer != null)
                  _TimerAlertOverlay(
                    timer: timer,
                    onStop: () => widget.store.finishStudyTimer(timer.id),
                  ),
              ],
            );
          },
        ),
        home: const HomePage(),
      ),
    );
  }
}

class _TimerAlertOverlay extends StatelessWidget {
  final StudyTimer timer;
  final Future<void> Function() onStop;

  const _TimerAlertOverlay({required this.timer, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final isAlarm = timer.kind == StudyTimerKind.alarm;
    return PopScope(
      canPop: false,
      child: Material(
        color: primary700,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Icon(
                  isAlarm ? Icons.alarm_on_rounded : Icons.timer_rounded,
                  color: Colors.white,
                  size: 76,
                ),
                const SizedBox(height: 28),
                Text(
                  isAlarm ? '闹钟时间到' : '计时完成',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  timer.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 19),
                ),
                const Spacer(),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: () async => onStop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primary700,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text(
                      '停止提醒',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
