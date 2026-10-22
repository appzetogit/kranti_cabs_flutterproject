import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/snackbar_utils.dart';
import '../application/ride_bids_controller.dart';
import '../data/models/ride_bid_model.dart';

/// Where the rider picks a driver by price, on an outstation bidding ride.
///
/// Bids stream in as drivers place them, cheapest first, and stay live until
/// one is accepted. Nothing auto-selects: the cheapest bid is highlighted but
/// the rider may prefer a higher-rated driver, and choosing for them would take
/// away the only reason this screen exists.
class RideBidsScreen extends ConsumerStatefulWidget {
  final String rideId;

  const RideBidsScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideBidsScreen> createState() => _RideBidsScreenState();
}

class _RideBidsScreenState extends ConsumerState<RideBidsScreen> {
  static const _bg = Color(0xFF11191D);
  static const _card = Color(0xFF222222);
  static const _border = Color(0xFF2E2E2E);
  static const _teal = Color(0xFFF5B400);
  static const _muted = Color(0xFF94A3B8);

  Future<void> _accept(RideBidModel bid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Accept this bid?', style: TextStyle(color: Colors.white, fontSize: 17)),
        content: Text(
          '${bid.driverName.isEmpty ? 'This driver' : bid.driverName} will take you '
          'for ₹${bid.bidFare.toStringAsFixed(0)}. Your trip starts once you accept.',
          style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep waiting', style: TextStyle(color: _muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: _bg),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ref.read(rideBidsControllerProvider(widget.rideId).notifier).acceptBid(bid.id);
    if (!mounted) return;

    if (ok) {
      context.pushReplacement('/ride/tracking/${widget.rideId}');
    } else {
      final error = ref.read(rideBidsControllerProvider(widget.rideId)).error;
      SnackbarUtils.error(context, error ?? 'That bid is no longer available.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rideBidsControllerProvider(widget.rideId));
    final controller = ref.read(rideBidsControllerProvider(widget.rideId).notifier);
    final bids = state.pendingBids;
    final bidding = state.bidding;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Driver offers',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _BandCard(
              bidding: bidding,
              bidCount: bids.length,
              raising: state.raising,
              onRaise: bidding.canRaise ? controller.raiseCeiling : null,
            ),

            if (state.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5),
                ),
              ),

            Expanded(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator(color: _teal))
                  : bids.isEmpty
                      ? _WaitingForBids(ceiling: bidding.userMaxBidFare)
                      : RefreshIndicator(
                          onRefresh: controller.load,
                          color: _teal,
                          backgroundColor: _card,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                            itemCount: bids.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, index) => _BidTile(
                              bid: bids[index],
                              // Cheapest sorts first, so the flag is positional
                              // rather than a second comparison that could
                              // disagree with the ordering.
                              isCheapest: index == 0 && bids.length > 1,
                              baseFare: bidding.baseFare,
                              busy: state.acceptingBidId == bids[index].id,
                              disabled: state.acceptingBidId != null,
                              onAccept: () => _accept(bids[index]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The band the rider set, and the lever to widen it.
class _BandCard extends StatelessWidget {
  final RideBiddingInfo bidding;
  final int bidCount;
  final bool raising;
  final VoidCallback? onRaise;

  const _BandCard({
    required this.bidding,
    required this.bidCount,
    required this.raising,
    this.onRaise,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _RideBidsScreenState._card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _RideBidsScreenState._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR MAXIMUM',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w900,
                        color: _RideBidsScreenState._muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '₹${bidding.userMaxBidFare.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      bidCount == 0
                          ? 'No offers yet'
                          : '$bidCount driver${bidCount == 1 ? '' : 's'} offering',
                      style: const TextStyle(fontSize: 12, color: _RideBidsScreenState._muted),
                    ),
                  ],
                ),
              ),
              if (onRaise != null)
                SizedBox(
                  height: 42,
                  child: OutlinedButton.icon(
                    onPressed: raising ? null : onRaise,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _RideBidsScreenState._teal,
                      side: const BorderSide(color: _RideBidsScreenState._teal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
                    ),
                    icon: raising
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _RideBidsScreenState._teal),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      '₹${bidding.bidStepAmount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
          if (onRaise == null) ...[
            const SizedBox(height: 8),
            const Text(
              "You've reached the highest fare allowed for this trip.",
              style: TextStyle(fontSize: 11, color: _RideBidsScreenState._muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _WaitingForBids extends StatelessWidget {
  final double ceiling;

  const _WaitingForBids({required this.ceiling});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
      children: [
        const Center(
          child: SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 2.6, color: _RideBidsScreenState._teal),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Waiting for drivers to bid',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Drivers nearby can see your trip and will send what they want to '
          'charge, up to ₹${ceiling.toStringAsFixed(0)}. Raise your maximum to '
          'reach more of them.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, height: 1.5, color: _RideBidsScreenState._muted),
        ),
      ],
    );
  }
}

class _BidTile extends StatelessWidget {
  final RideBidModel bid;
  final bool isCheapest;
  final double baseFare;
  final bool busy;
  final bool disabled;
  final VoidCallback onAccept;

  const _BidTile({
    required this.bid,
    required this.isCheapest,
    required this.baseFare,
    required this.busy,
    required this.disabled,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final difference = bid.bidFare - baseFare;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: _RideBidsScreenState._card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCheapest
              ? _RideBidsScreenState._teal.withValues(alpha: 0.6)
              : _RideBidsScreenState._border,
          width: isCheapest ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCheapest) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _RideBidsScreenState._teal.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'LOWEST OFFER',
                style: TextStyle(
                  fontSize: 8.5,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w900,
                  color: _RideBidsScreenState._teal,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF11191D),
                backgroundImage: bid.driverImage.isEmpty ? null : NetworkImage(bid.driverImage),
                child: bid.driverImage.isEmpty
                    ? const Icon(Icons.person_rounded, color: _RideBidsScreenState._muted, size: 22)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bid.driverName.isEmpty ? 'Driver' : bid.driverName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (bid.driverRating > 0) ...[
                          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFBBF24)),
                          const SizedBox(width: 3),
                          Text(
                            bid.driverRating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Flexible(
                          child: Text(
                            bid.vehicleLabel.isEmpty ? bid.vehicleNumber : bid.vehicleLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: _RideBidsScreenState._muted),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${bid.bidFare.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  if (difference != 0)
                    Text(
                      difference < 0
                          ? '₹${difference.abs().toStringAsFixed(0)} below quote'
                          : '₹${difference.toStringAsFixed(0)} above quote',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: difference < 0
                            ? const Color(0xFF34D399)
                            : const Color(0xFFFBBF24),
                      ),
                    ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _RideBidsScreenState._teal,
                foregroundColor: _RideBidsScreenState._bg,
                disabledBackgroundColor: const Color(0xFF16283A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21)),
              ),
              onPressed: disabled ? null : onAccept,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _RideBidsScreenState._bg),
                    )
                  : Text(
                      'Accept ₹${bid.bidFare.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
