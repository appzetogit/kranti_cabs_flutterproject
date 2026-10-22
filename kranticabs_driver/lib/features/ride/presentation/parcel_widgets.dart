import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/image_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../data/parcel_info.dart';

/// Everything the sender declared about the parcel.
///
/// Shown on the offer *before* the driver accepts, and again on the active ride,
/// because the answer to "can my vehicle take this?" is the same question in
/// both places. The offer screen is dark and the active ride sheet is light, so
/// the palette is passed in rather than read from the theme.
class ParcelDetailsCard extends StatelessWidget {
  final ParcelInfo parcel;
  final bool dark;

  /// Trimmed down for the offer card, where the driver has seconds to decide
  /// and the contact numbers are not yet theirs to call.
  final bool compact;

  const ParcelDetailsCard({
    super.key,
    required this.parcel,
    required this.dark,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (parcel.isEmpty) return const SizedBox.shrink();

    final surface = dark ? const Color(0xFF11191D) : const Color(0xFFF8FAFC);
    final border = dark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E8F0);
    final textPrimary = dark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_rounded, size: 16, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 8),
              Text(
                'PARCEL DETAILS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w900,
                  color: textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (parcel.title.isNotEmpty)
            _Line(
              icon: Icons.category_outlined,
              label: 'Contents',
              value: parcel.title,
              textPrimary: textPrimary,
              textMuted: textMuted,
            ),

          // Only when it adds something: with no free-text description the
          // title already *is* the category, and repeating it reads as a bug.
          if (parcel.category.isNotEmpty && parcel.description.isNotEmpty)
            _Line(
              icon: Icons.label_outline_rounded,
              label: 'Type',
              value: parcel.category,
              textPrimary: textPrimary,
              textMuted: textMuted,
            ),

          if (parcel.weight.isNotEmpty)
            _Line(
              icon: Icons.scale_outlined,
              label: 'Weight',
              value: parcel.weight,
              textPrimary: textPrimary,
              textMuted: textMuted,
            ),

          if (parcel.instructions.isNotEmpty)
            _Line(
              icon: Icons.priority_high_rounded,
              label: 'Instructions',
              value: parcel.instructions,
              textPrimary: const Color(0xFFF59E0B),
              textMuted: textMuted,
            ),

          if (!compact) ...[
            if (parcel.senderName.isNotEmpty)
              _Line(
                icon: Icons.person_outline_rounded,
                label: 'Sender',
                value: parcel.senderMobile.isEmpty
                    ? parcel.senderName
                    : '${parcel.senderName} · ${parcel.senderMobile}',
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
            if (parcel.receiverName.isNotEmpty)
              _Line(
                icon: Icons.where_to_vote_outlined,
                label: 'Receiver',
                value: parcel.receiverMobile.isEmpty
                    ? parcel.receiverName
                    : '${parcel.receiverName} · ${parcel.receiverMobile}',
                textPrimary: textPrimary,
                textMuted: textMuted,
              ),
          ],

          if (parcel.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              "SENDER'S PHOTOS",
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w900,
                color: textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: parcel.photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) => _Thumb(
                  url: parcel.photos[index],
                  border: border,
                  onTap: () => showParcelPhotoViewer(context, parcel.photos, index),
                ),
              ),
            ),
          ],

          if (!compact && (parcel.pickupProof.exists || parcel.deliveryProof.exists)) ...[
            const SizedBox(height: 10),
            Text(
              "HANDOVER PROOF PHOTOS",
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w900,
                color: textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (parcel.pickupProof.exists)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Thumb(
                          url: parcel.pickupProof.url,
                          border: border,
                          onTap: () => showParcelPhotoViewer(context, [parcel.pickupProof.url], 0),
                        ),
                        const SizedBox(height: 3),
                        Text('Pickup Proof', style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                if (parcel.deliveryProof.exists)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Thumb(
                        url: parcel.deliveryProof.url,
                        border: border,
                        onTap: () => showParcelPhotoViewer(context, [parcel.deliveryProof.url], 0),
                      ),
                      const SizedBox(height: 3),
                      Text('Delivery Proof', style: TextStyle(fontSize: 10, color: textMuted, fontWeight: FontWeight.w700)),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The photo gate on the active ride.
///
/// A parcel trip cannot start until the driver photographs what they collected,
/// and cannot be completed until they photograph the hand-over. This states that
/// plainly rather than letting the driver press a button that the server will
/// reject.
class ParcelProofStep extends StatelessWidget {
  /// 'pickup' or 'delivery'.
  final String stage;
  final ParcelProof proof;
  final bool busy;
  final VoidCallback onCapture;

  const ParcelProofStep({
    super.key,
    required this.stage,
    required this.proof,
    required this.busy,
    required this.onCapture,
  });

  bool get _isPickup => stage == 'pickup';

  @override
  Widget build(BuildContext context) {
    final done = proof.exists;
    final accent = done ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: done ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                done ? Icons.verified_rounded : Icons.photo_camera_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  done
                      ? (_isPickup ? 'Pickup photo saved' : 'Delivery photo saved')
                      : (_isPickup ? 'Photograph the parcel' : 'Photograph the delivery'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            done
                ? (_isPickup
                    ? 'You can start the trip now. Retake it if the photo is unclear.'
                    : 'You can complete the trip now. Retake it if the photo is unclear.')
                : (_isPickup
                    ? 'Take a photo of the parcel as you collect it. The trip cannot start without it.'
                    : 'Take a photo of the parcel with the receiver. The trip cannot be completed without it.'),
            style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              if (done) ...[
                _Thumb(
                  url: proof.url,
                  border: const Color(0xFFCBD5E1),
                  onTap: () => showParcelPhotoViewer(context, [proof.url], 0),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onCapture,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: BorderSide(color: accent.withValues(alpha: 0.7), width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(done ? Icons.refresh_rounded : Icons.photo_camera_rounded, size: 18),
                    label: Text(
                      busy ? 'Uploading…' : (done ? 'Retake photo' : 'Take photo'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Full-screen look at a parcel photo, swipeable when there is more than one.
///
/// Worth the screen: the driver is comparing what is in front of them against
/// what the sender photographed, and a 64-pixel thumbnail settles nothing.
void showParcelPhotoViewer(BuildContext context, List<String> urls, int initialIndex) {
  if (urls.isEmpty) return;

  final controller = PageController(initialPage: initialIndex.clamp(0, urls.length - 1));

  showDialog<void>(
    context: context,
    barrierColor: const Color(0xE6000000),
    builder: (dialogContext) => Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: controller,
            itemCount: urls.length,
            itemBuilder: (_, index) => InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: resolveMediaUrl(urls[index]),
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
  ).whenComplete(controller.dispose);
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textPrimary;
  final Color textMuted;

  const _Line({
    required this.icon,
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: textMuted),
          const SizedBox(width: 9),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final Color border;
  final VoidCallback onTap;

  const _Thumb({required this.url, required this.border, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: CachedNetworkImage(
          imageUrl: resolveMediaUrl(url),
          fit: BoxFit.cover,
          placeholder: (_, _) => const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
          ),
          errorWidget: (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined, size: 18, color: Color(0xFF94A3B8)),
          ),
        ),
      ),
    );
  }
}
