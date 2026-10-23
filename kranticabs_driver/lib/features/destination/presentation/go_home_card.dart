import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/destination_providers.dart';
import '../data/destination_mode.dart';

/// Home-screen card for destination mode ("Go Home").
///
/// Off: a "Go Home" button (or "Set your home" when none is saved). On: who
/// the driver is heading to, that only rides on the way will come, and a
/// Turn off button. Hidden while the admin has the feature switched off.
class GoHomeCard extends ConsumerStatefulWidget {
  const GoHomeCard({super.key});

  @override
  ConsumerState<GoHomeCard> createState() => _GoHomeCardState();
}

class _GoHomeCardState extends ConsumerState<GoHomeCard> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (error) {
      SnackbarUtils.error(error.message);
    } catch (_) {
      SnackbarUtils.error('Could not update Go Home. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(destinationModeProvider).valueOrNull;
    if (info == null || !info.featureEnabled) return const SizedBox.shrink();

    final notifier = ref.read(destinationModeProvider.notifier);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: info.enabled ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: info.enabled ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: info.enabled ? AppColors.primary : const Color(0xFFFFF4CC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.home_rounded, color: info.enabled ? const Color(0xFF0F172A) : const Color(0xFFB45309)),
          ),
          const SizedBox(width: 12),
          Expanded(child: _texts(info)),
          const SizedBox(width: 8),
          _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
              : _action(context, info, notifier),
        ],
      ),
    );
  }

  Widget _texts(DestinationModeInfo info) {
    final title = info.enabled
        ? 'Heading to ${info.destinationLabel.isEmpty ? (info.isHome ? 'home' : 'your destination') : info.destinationLabel}'
        : 'Going home?';
    final subtitle = info.enabled
        ? 'Only rides on your way. Turns off when you arrive.'
        : !info.hasHome
            ? 'Save your home to get rides on the way there.'
            : info.usesLeft == 0
                ? 'Used ${info.usedToday}/${info.usesPerDay} times today.'
                : 'Get only rides towards home${info.usesLeft != null ? ' · ${info.usesLeft} left today' : ''}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: info.enabled ? Colors.white : const Color(0xFF0F172A),
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: info.enabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _action(BuildContext context, DestinationModeInfo info, DestinationModeNotifier notifier) {
    if (info.enabled) {
      return TextButton(
        onPressed: () => _act(notifier.turnOff),
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
        child: const Text('Turn off', style: TextStyle(fontWeight: FontWeight.w800)),
      );
    }
    if (!info.hasHome) {
      return TextButton(
        onPressed: () => context.push('/home-location'),
        child: const Text('Set home', style: TextStyle(fontWeight: FontWeight.w800)),
      );
    }
    return ElevatedButton(
      onPressed: info.usesLeft == 0 ? null : () => _act(notifier.goHome),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFF0F172A),
        // The app theme makes buttons full width; in a row that squeezes the
        // text into nothing.
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text('Go Home', style: TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
