import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/alerts/alerts_providers.dart';

/// Off in tests that don't want timers.
final foregroundChecksEnabledProvider = Provider<bool>((ref) => true);

/// "Checks while app is open" (spec §4): while the app is in the
/// foreground, look for due alerts every [tick] and on resume. Only alerts
/// whose interval has passed are fetched, so this adds no extra requests
/// beyond each alert's schedule. On iOS it is the only automatic check.
class ForegroundChecker extends ConsumerStatefulWidget {
  const ForegroundChecker({
    super.key,
    required this.child,
    this.tick = const Duration(minutes: 1),
  });

  final Widget child;
  final Duration tick;

  @override
  ConsumerState<ForegroundChecker> createState() => _ForegroundCheckerState();
}

class _ForegroundCheckerState extends ConsumerState<ForegroundChecker> {
  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (!ref.read(foregroundChecksEnabledProvider)) return;
    _lifecycle = AppLifecycleListener(onResume: _start, onPause: _stop);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.tick, (_) => _check());
    _check();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_running || !mounted) return;
    _running = true;
    try {
      await ref.read(alertsControllerProvider).runDue();
    } catch (e) {
      debugPrint('ShowWatch in-app check failed: $e');
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    _stop();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
