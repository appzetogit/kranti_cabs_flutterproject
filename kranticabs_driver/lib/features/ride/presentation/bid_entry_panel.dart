import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Where the driver names their price on a bidding offer.
///
/// Replaces Accept rather than sitting beside it: the server refuses a plain
/// accept on a bidding ride ("Bidding rides must be won through bid
/// acceptance"), so offering both buttons would put one there that always
/// fails.
///
/// The stepper is clamped to the server's own band and increment, because a bid
/// outside it is rejected with an error the driver can do nothing about after
/// the fact.
class BidEntryPanel extends StatefulWidget {
  /// The rider's quoted fare, and the anchor the step arithmetic runs from.
  final num baseFare;

  final num floorFare;
  final num ceilingFare;
  final num stepAmount;

  /// Set once the server confirmed a bid, which switches this to a waiting
  /// state instead of an editable stepper.
  final num? submittedFare;

  final bool busy;
  final void Function(num bidFare) onSubmit;

  const BidEntryPanel({
    super.key,
    required this.baseFare,
    required this.floorFare,
    required this.ceilingFare,
    required this.stepAmount,
    required this.submittedFare,
    required this.busy,
    required this.onSubmit,
  });

  @override
  State<BidEntryPanel> createState() => _BidEntryPanelState();
}

class _BidEntryPanelState extends State<BidEntryPanel> {
  late num _bid = _startingBid();

  static const _surface = Color(0xFF11191D);
  static const _border = Color(0xFF2E2E2E);
  static const _muted = Color(0xFF94A3B8);

  /// Opens at the rider's own fare where that is legal.
  ///
  /// The quoted fare is the bid most likely to be accepted, and starting at the
  /// floor would nudge every driver into undercutting by default.
  num _startingBid() {
    final base = widget.baseFare;
    if (base >= _floor && base <= _ceiling) return base;
    return base < _floor ? _floor : _ceiling;
  }

  num get _floor => widget.floorFare > 0 ? widget.floorFare : widget.baseFare;

  num get _ceiling =>
      widget.ceilingFare > 0 && widget.ceilingFare >= _floor ? widget.ceilingFare : widget.baseFare;

  num get _step => widget.stepAmount > 0 ? widget.stepAmount : 10;

  void _move(int steps) {
    final next = _bid + (_step * steps);
    if (next < _floor || next > _ceiling) return;
    setState(() => _bid = next);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = widget.submittedFare;

    if (submitted != null) {
      return _WaitingCard(bidFare: submitted);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Name your price',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
              Text(
                'Rider asked ₹${widget.baseFare.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: _bid - _step < _floor ? null : () => _move(-1),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '₹${_bid.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${_floor.toStringAsFixed(0)} – ₹${_ceiling.toStringAsFixed(0)} allowed',
                      style: const TextStyle(fontSize: 10.5, color: _muted),
                    ),
                  ],
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: _bid + _step > _ceiling ? null : () => _move(1),
              ),
            ],
          ),

          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: _surface,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: widget.busy ? null : () => widget.onSubmit(_bid),
              icon: widget.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: _surface),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                widget.busy ? 'Sending…' : 'Send bid of ₹${_bid.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'The rider compares bids and picks one. A lower bid usually wins faster.',
            style: TextStyle(fontSize: 10.5, height: 1.35, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final num bidFare;

  const _WaitingCard({required this.bidFare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: _BidEntryPanelState._surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bid sent — ₹${bidFare.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Waiting for the rider to choose. You can keep driving — '
                  "you'll be notified if they pick you.",
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: _BidEntryPanelState._muted,
                  ),
                ),
              ],
            ),
          ),
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
      color: disabled ? const Color(0xFF16283A) : const Color(0xFF222222),
      shape: CircleBorder(
        side: BorderSide(color: disabled ? _BidEntryPanelState._border : AppColors.primary),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(
            icon,
            size: 22,
            color: disabled ? const Color(0xFF48607A) : AppColors.primary,
          ),
        ),
      ),
    );
  }
}
