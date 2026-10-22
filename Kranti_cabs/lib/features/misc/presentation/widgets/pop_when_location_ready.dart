import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/core_providers.dart';
import '../../../../core/services/location_service.dart';
import '../../../home/application/home_providers.dart';

/// Closes a "turn on location" screen by itself once the rider has fixed it.
///
/// Both fixes - switching GPS on, allowing the permission - happen in system
/// settings, outside the app. Without this the rider came back to the same
/// screen still asking them to do what they had just done, with no way to tell
/// it had worked.
class PopWhenLocationReady extends ConsumerStatefulWidget {
  /// Whether the rider has done what this screen asked.
  final bool Function(LocationPermissionResult status) isReady;
  final Widget child;

  const PopWhenLocationReady({
    super.key,
    required this.isReady,
    required this.child,
  });

  @override
  ConsumerState<PopWhenLocationReady> createState() => _PopWhenLocationReadyState();
}

class _PopWhenLocationReadyState extends ConsumerState<PopWhenLocationReady>
    with WidgetsBindingObserver {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_closing) return;
    final status = await ref.read(locationServiceProvider).checkStatus();
    if (!mounted || !widget.isReady(status)) return;

    _closing = true;
    // Fetch again now rather than leave every screen holding the "no
    // location" it worked out before.
    ref.invalidate(locationStatusProvider);
    ref.invalidate(currentPositionProvider);
    Navigator.of(context).maybePop(true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
