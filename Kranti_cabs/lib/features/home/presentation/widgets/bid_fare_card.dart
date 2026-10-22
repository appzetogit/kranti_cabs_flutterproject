import 'package:flutter/material.dart';

/// Lets the rider name their own price instead of taking the quoted fare.
///
/// What switching this on actually does depends on the trip, and the copy says
/// so plainly rather than pretending they are the same thing:
///
///  * **Outstation** — the ride opens for bids and drivers offer their price.
///    The stepper sets the most the rider will pay; drivers cannot ask more.
///  * **City** — no bids exist. The fare instead starts *above* the quote (the
///    server lifts it to the user floor) and the rider can raise it further
///    from the search screen. The higher starting figure is shown up front,
///    because agreeing to "name your own price" and silently paying more than
///    the quote is not a trade anyone opted into.
///
/// The distinction is the backend's, not a UI choice: `createRideRecord` routes
/// city rides to `user_increment_only`, where a ceiling would be meaningless.
class BidFareCard extends StatelessWidget {
  final bool enabled;
  final bool isOutstation;

  /// The fare the app quoted, and the floor for any ceiling.
  final double quotedFare;

  /// The rider's current ceiling. Equals [quotedFare] until they raise it.
  final double bidMaxFare;

  /// Increment configured by the admin, in rupees.
  final double stepAmount;

  /// What a city ride will actually start at once bidding is on. Ignored for
  /// outstation, where the quoted fare stands and only the ceiling moves.
  final double cityStartingFare;

  final ValueChanged<bool> onToggle;
  final void Function(int steps) onAdjust;

  const BidFareCard({
    super.key,
    required this.enabled,
    required this.isOutstation,
    required this.quotedFare,
    required this.bidMaxFare,
    required this.stepAmount,
    required this.cityStartingFare,
    required this.onToggle,
    required this.onAdjust,
  });

  static const _card = Color(0xFF161616);
  static const _border = Color(0xFF2A2A2A);
  static const _teal = Color(0xFFF5B400);
  static const _muted = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final ceiling = bidMaxFare > 0 ? bidMaxFare : quotedFare;
    final difference = ceiling - quotedFare;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: enabled ? _teal.withValues(alpha: 0.55) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, color: _teal, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Name your own price',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOutstation
                          ? 'Drivers send you their price and you pick one'
                          : 'Start higher so drivers accept sooner, and raise it '
                              'further if nobody takes the trip',
                      style: const TextStyle(fontSize: 11.5, height: 1.35, color: _muted),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                activeThumbColor: _teal,
                onChanged: onToggle,
              ),
            ],
          ),

          // City rides have no ceiling to set, but they do change price the
          // moment this is switched on, so the new figure is stated plainly.
          if (enabled && !isOutstation && cityStartingFare > quotedFare) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 15, color: _teal),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Your fare becomes ₹${cityStartingFare.toStringAsFixed(0)} '
                      'instead of ₹${quotedFare.toStringAsFixed(0)}.',
                      style: const TextStyle(fontSize: 11.5, height: 1.35, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // The ceiling only exists for outstation. Showing a stepper on a city
          // ride would imply a limit the server never applies.
          if (enabled && isOutstation) ...[
            const SizedBox(height: 14),
            const Divider(color: _border, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MOST I WILL PAY',
                        style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w900,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '₹${ceiling.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        difference <= 0
                            ? 'Same as the quoted fare'
                            : '₹${difference.toStringAsFixed(0)} above the quoted ₹${quotedFare.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                    ],
                  ),
                ),
                _StepButton(
                  icon: Icons.remove_rounded,
                  // Never below the quote: a ceiling under it cannot attract a
                  // legal bid, so the button is dead rather than misleading.
                  onTap: ceiling - stepAmount < quotedFare ? null : () => onAdjust(-1),
                ),
                const SizedBox(width: 10),
                _StepButton(icon: Icons.add_rounded, onTap: () => onAdjust(1)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Raising this attracts more drivers. The final price is whichever '
              'bid you accept — never more than this.',
              style: TextStyle(fontSize: 10.5, height: 1.4, color: _muted.withValues(alpha: 0.85)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Material(
      color: disabled ? const Color(0xFF16283A) : const Color(0xFF0A0A0A),
      shape: CircleBorder(
        side: BorderSide(color: disabled ? const Color(0xFF2A2A2A) : BidFareCard._teal),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 20,
            color: disabled ? const Color(0xFF48607A) : BidFareCard._teal,
          ),
        ),
      ),
    );
  }
}
