import 'dart:async';

import 'package:flutter/material.dart';

import 'features/home/home_page.dart';
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
        home: const HomePage(),
      ),
    );
  }
}
