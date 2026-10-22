import '../../../../core/utils/image_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../delivery/data/models/parcel_model.dart';

/// The two photos the delivery captain takes, shown to the sender.
///
/// This is the whole reason the proof photos exist: the sender sees the parcel
/// in the captain's hands at collection, and handed over at the far end. Used
/// on the live tracking screen, where the tiles fill in as each photo lands,
/// and again on the completed-delivery record, where both are already there.
///
/// A missing photo reads as "Waiting" rather than as an error, because before
/// the captain reaches the pickup that is exactly what it is.
class ParcelProofStrip extends StatelessWidget {
  final ParcelProof pickup;
  final ParcelProof delivery;

  /// Photos the sender took when booking. Shown alongside the captain's on the
  /// completed record, where the point is comparing the two.
  final List<String> senderPhotos;

  /// Tighter styling for the live tracking sheet, which is already crowded.
  final bool compact;

  const ParcelProofStrip({
    super.key,
    required this.pickup,
    required this.delivery,
    this.senderPhotos = const [],
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 15, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 8),
              Text(
                'PARCEL PROOF',
                style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w900,
                  color: textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _ProofTile(
                  label: 'Picked up',
                  proof: pickup,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  border: border,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ProofTile(
                  label: 'Delivered',
                  proof: delivery,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  border: border,
                ),
              ),
            ],
          ),

          if (!compact && senderPhotos.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'PHOTOS YOU SENT',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w900,
                color: textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: senderPhotos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => showParcelPhoto(context, senderPhotos[index]),
                  child: Container(
                    width: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: CachedNetworkImage(
                      imageUrl: resolveMediaUrl(senderPhotos[index]),
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Icon(
                        Icons.broken_image_outlined,
                        size: 18,
                        color: textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProofTile extends StatelessWidget {
  final String label;
  final ParcelProof proof;
  final Color textPrimary;
  final Color textMuted;
  final Color border;

  const _ProofTile({
    required this.label,
    required this.proof,
    required this.textPrimary,
    required this.textMuted,
    required this.border,
  });

  String get _time {
    final stamp = proof.at;
    if (stamp == null) return 'Waiting';

    final hour = stamp.hour % 12 == 0 ? 12 : stamp.hour % 12;
    final minute = stamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${stamp.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final done = proof.url.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.35,
          child: GestureDetector(
            onTap: done ? () => showParcelPhoto(context, proof.url) : null,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFEFF3F8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: done ? const Color(0xFF10B981) : border),
              ),
              clipBehavior: Clip.antiAlias,
              child: done
                  ? CachedNetworkImage(
                      imageUrl: resolveMediaUrl(proof.url),
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, _, _) => const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    )
                  : const Center(
                      child: Icon(
                        Icons.hourglass_empty_rounded,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: textPrimary),
        ),
        Text(
          _time,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: done ? const Color(0xFF10B981) : textMuted,
          ),
        ),
      ],
    );
  }
}

/// Opens one photo full screen, pinch-zoomable.
///
/// Worth a whole screen: the sender is checking the state of their parcel, and
/// a thumbnail settles nothing.
void showParcelPhoto(BuildContext context, String url) {
  if (url.isEmpty) return;

  showDialog<void>(
    context: context,
    barrierColor: const Color(0xE6000000),
    builder: (dialogContext) => Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: resolveMediaUrl(url),
                fit: BoxFit.contain,
                placeholder: (_, _) => const CircularProgressIndicator(color: Colors.white),
                errorWidget: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  size: 44,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(dialogContext).padding.top + 8,
          right: 12,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ],
    ),
  );
}
