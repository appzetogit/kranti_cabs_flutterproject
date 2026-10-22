import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ride/data/models/ride_bid_model.dart';

/// The city-ride half of bidding: no drivers bid, the rider sweetens their own
/// fare and dispatch goes round again at the higher price.
///
/// Several amounts are offered rather than one, because a rider who has been
/// waiting usually knows what the trip is worth to them - making them add ten
/// rupees at a time, with a cooling-off period between each, is the slowest
/// possible way to find that out.
///
/// The wait (`user_fare_increase_wait_minutes`, 2 by default) still sits
/// between raises. The countdown is shown rather than just disabling the
/// buttons, because a dead button with no explanation reads as a bug.
class RaiseFareCard extends StatefulWidget {
  final RideBiddingInfo bidding;

  /// Current fare, which for this mode *is* what the rider will pay.
  final double currentFare;

  final bool busy;

  /// Called with how many [RideBiddingInfo.bidStepAmount] steps to add.
  final ValueChanged<int> onRaise;

  const RaiseFareCard({
    super.key,
    required this.bidding,
    required this.currentFare,
    required this.busy,
    required this.onRaise,
  });

  /// Most amounts offered at once. Four is what fits on one row at phone width
  /// without the labels shrinking to nothing.
  static const int maxOptions = 4;

  @override
  State<RaiseFareCard> createState() => _RaiseFareCardState();
}

class _RaiseFareCardState extends State<RaiseFareCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Redraws only the countdown label. One second is the resolution the label
    // is written at, so anything finer would be wasted frames.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _countdown(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }

  String _rupees(double amount) => '₹${amount.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final chipBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final chipBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final waitSeconds = widget.bidding.secondsUntilRaise;
    final step = widget.bidding.bidStepAmount;
    // One option per remaining step, capped. At the ceiling this is empty and
    // the card says so instead of offering nothing.
    final remaining = widget.bidding.remainingRaiseSteps;
    final optionCount =
        remaining < RaiseFareCard.maxOptions ? remaining : RaiseFareCard.maxOptions;
    final atCeiling = optionCount == 0;
    final canRaise = !atCeiling && waitSeconds == 0 && !widget.busy;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        border: Border.fromBorderSide(BorderSide(color: cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up_rounded, size: 18, color: Color(0xFFF5B400)),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  atCeiling
                      ? 'Still looking for a driver'
                      : "Captains aren't accepting at ${_rupees(widget.currentFare)}",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: textPrimary),
                ),
              ),
              Text(
                _rupees(widget.currentFare),
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            atCeiling
                ? 'This is the highest fare allowed for this trip. Keep waiting - drivers are still being contacted.'
                : 'Try adding more to get matched faster.',
            style: TextStyle(fontSize: 11.5, height: 1.4, color: textMuted),
          ),
          if (!atCeiling) ...[
            const SizedBox(height: 12),

            // One tap per amount, each carrying the fare it lands on, so nobody
            // adds forty rupees without seeing what they end up paying.
            Row(
              children: [
                for (var steps = 1; steps <= optionCount; steps++) ...[
                  if (steps > 1) const SizedBox(width: 8),
                  Expanded(
                    child: _RaiseOption(
                      label: '+ ${_rupees(step * steps)}',
                      resultingFare: _rupees(widget.currentFare + (step * steps)),
                      background: chipBg,
                      border: chipBorder,
                      textColor: textPrimary,
                      mutedColor: textMuted,
                      enabled: canRaise,
                      onTap: () => widget.onRaise(steps),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.busy) ...[
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF5B400)),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Updating your fare...',
                      style: TextStyle(fontSize: 10.5, color: textMuted),
                    ),
                  ),
                ] else if (waitSeconds > 0) ...[
                  Icon(Icons.schedule_rounded, size: 13, color: textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'You can add again in ${_countdown(waitSeconds)}',
                      style: TextStyle(fontSize: 10.5, color: textMuted),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      'Up to ${_rupees(widget.bidding.bidCeilingMaxFare)} for this trip.',
                      style: TextStyle(fontSize: 10.5, color: textMuted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One amount the rider can add, with the fare it lands on underneath.
class _RaiseOption extends StatelessWidget {
  final String label;
  final String resultingFare;
  final Color background;
  final Color border;
  final Color textColor;
  final Color mutedColor;
  final bool enabled;
  final VoidCallback onTap;

  const _RaiseOption({
    required this.label,
    required this.resultingFare,
    required this.background,
    required this.border,
    required this.textColor,
    required this.mutedColor,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: background,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              border: Border.fromBorderSide(BorderSide(color: border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: textColor),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    resultingFare,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: mutedColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
