import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../application/home_providers.dart';

/// Re-reads the rider's location whenever the app comes back to the
/// foreground.
///
/// The position is resolved once and kept. That was the whole of the
/// "stuck on Fetching location" bug: a rider who said no at first launch,
/// then allowed location in Settings - or switched GPS on from the quick
/// settings panel - came back to an app still holding the "no location" it
/// had worked out before, with nothing ever asking again.
///
/// Both of those changes happen outside the app, so returning to it is
/// exactly the moment the answer may have changed.
class LocationRefresher extends ConsumerStatefulWidget {
  final Widget child;
  const LocationRefresher({super.key, required this.child});

  @override
  ConsumerState<LocationRefresher> createState() => _LocationRefresherState();
}

class _LocationRefresherState extends ConsumerState<LocationRefresher>
    with WidgetsBindingObserver {
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
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    // Read the state without prompting: asking for permission every time the
    // app is reopened would nag a rider who deliberately said no.
    final status = await ref.read(locationServiceProvider).checkStatus();
    if (!mounted) return;

    ref.invalidate(locationStatusProvider);

    // Only re-fetch when it can now succeed, and only when the last attempt
    // came back empty. A rider who already has a position keeps it - the map
    // tracks movement separately - so this costs nothing in the normal case.
    final hadPosition = ref.read(currentPositionProvider).valueOrNull != null;
    if (status.granted && !hadPosition) {
      ref.invalidate(currentPositionProvider);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
