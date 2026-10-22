import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../application/delivery_booking_controller.dart';
import '../application/delivery_providers.dart';
import '../data/models/goods_type_model.dart';

/// What is actually in the box.
///
/// Sits between the receiver's details and the booking itself because the
/// driver needs all of it before they accept: what they are carrying, how heavy
/// it is, what it looks like, and anything special about handling it. Bundling
/// this into the contacts sheet was not an option — the photos need room.
///
/// Pops `true` once saved, so the address screen can carry straight on to
/// booking; popping without saving leaves the booking untouched.
class ParcelDetailsScreen extends ConsumerStatefulWidget {
  const ParcelDetailsScreen({super.key});

  @override
  ConsumerState<ParcelDetailsScreen> createState() => _ParcelDetailsScreenState();
}

class _ParcelDetailsScreenState extends ConsumerState<ParcelDetailsScreen> {
  /// Two is the cap the server enforces, so the UI offers exactly two slots
  /// rather than letting a sender add a third that would be silently dropped.
  static const int _maxPhotos = 2;

  static const List<String> _weightPresets = [
    'Under 1 kg',
    '1 - 5 kg',
    '5 - 10 kg',
    '10 - 20 kg',
    'Over 20 kg',
  ];

  late final TextEditingController _material;
  late final TextEditingController _weight;

  /// The sender must accept responsibility for the parcel's contents before
  /// continuing. Mandatory — Continue stays disabled until this is ticked.
  bool _consent = false;

  /// Hosted URLs of photos already uploaded. Uploading as they are picked means
  /// the Continue tap is instant instead of stalling on two uploads.
  List<String> _photos = [];

  /// Local previews, index-aligned with [_photos] where both exist. Kept so the
  /// tile shows the photo immediately rather than waiting on a network fetch of
  /// the image that was just sent.
  final Map<int, File> _previews = {};

  int? _uploadingSlot;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = ref.read(deliveryBookingProvider);
    _material = TextEditingController(text: state.category);
    _weight = TextEditingController(text: state.weight);
    _photos = List<String>.from(state.photos);
  }

  @override
  void dispose() {
    _material.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(int slot) async {
    final source = await _askSource();
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      // Trimmed hard on purpose: this is a proof photo viewed on a phone, and
      // it travels as base64, where a full-resolution image would be several
      // megabytes of request body.
      imageQuality: 70,
      maxWidth: 1280,
    );
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    setState(() {
      _uploadingSlot = slot;
      _previews[slot] = file;
      _error = null;
    });

    try {
      final url = await ref.read(deliveryRepositoryProvider).uploadParcelPhoto(file);
      if (!mounted) return;

      if (url.isEmpty) {
        setState(() {
          _uploadingSlot = null;
          _previews.remove(slot);
          _error = 'That photo could not be saved. Please try again.';
        });
        return;
      }

      setState(() {
        _uploadingSlot = null;
        final next = List<String>.from(_photos);
        if (slot < next.length) {
          next[slot] = url;
        } else {
          next.add(url);
        }
        _photos = next;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploadingSlot = null;
        _previews.remove(slot);
        _error = 'That photo could not be uploaded. Check your connection and try again.';
      });
    }
  }

  Future<ImageSource?> _askSource() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              title: const Text('Take a photo', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _removePhoto(int slot) {
    setState(() {
      final next = List<String>.from(_photos);
      if (slot < next.length) next.removeAt(slot);
      _photos = next;
      _previews.clear();
    });
  }

  void _save() {
    final material = _material.text.trim();
    final weight = _weight.text.trim();

    if (material.isEmpty) {
      setState(() => _error = 'Tell us what is inside the parcel');
      return;
    }
    if (weight.isEmpty) {
      setState(() => _error = 'Add an approximate weight');
      return;
    }
    // One photo is the floor, not two: a sender with a single clear shot of the
    // box should not be blocked, but a delivery with no photo at all leaves
    // nothing to compare the driver's hand-over photo against.
    if (_photos.isEmpty) {
      setState(() => _error = 'Add at least one photo of the parcel');
      return;
    }
    // The sender must accept responsibility for the parcel's contents before
    // booking a delivery.
    if (!_consent) {
      setState(() => _error = 'Please accept the responsibility declaration to continue');
      return;
    }

    ref.read(deliveryBookingProvider.notifier).setParcelDetails(
          category: material,
          weight: weight,
          photos: _photos,
          instructions: '',
        );

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final goodsTypes = ref.watch(goodsTypesProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B1220) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Parcel details',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Text(
              'The delivery captain sees all of this before accepting, so they '
              'arrive with the right vehicle and handle it properly.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 22),

            const _SectionLabel(
              icon: Icons.inventory_2_outlined,
              label: 'What is inside',
              color: Color(0xFF0EA5E9),
            ),
            const SizedBox(height: 10),
            // The catalog drives the chips, but the field is always editable:
            // an empty or unreachable catalog must not stop a booking, and the
            // server treats an unlisted material as unrestricted anyway.
            goodsTypes.when(
              data: (types) => types.isEmpty
                  ? const SizedBox.shrink()
                  : _MaterialChips(
                      types: types,
                      selected: _material.text.trim(),
                      onSelect: (name) => setState(() => _material.text = name),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
            _Field(
              controller: _material,
              hint: 'e.g. Documents, medicines, clothes',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            const _SectionLabel(
              icon: Icons.scale_outlined,
              label: 'Approximate weight',
              color: Color(0xFFF59E0B),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _weightPresets
                  .map((preset) => _Chip(
                        label: preset,
                        selected: _weight.text.trim() == preset,
                        onTap: () => setState(() => _weight.text = preset),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            _Field(
              controller: _weight,
              hint: 'Or type it, e.g. 3 kg',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            const _SectionLabel(
              icon: Icons.photo_camera_outlined,
              label: 'Photos of the parcel',
              color: Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 6),
            Text(
              'Up to two. The captain photographs the parcel again at pickup and '
              'at delivery, so these are what everyone compares against.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(_maxPhotos, (slot) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: slot == _maxPhotos - 1 ? 0 : 12),
                    child: _PhotoSlot(
                      url: slot < _photos.length ? _photos[slot] : null,
                      preview: _previews[slot],
                      uploading: _uploadingSlot == slot,
                      isDark: isDark,
                      onTap: () => _pickPhoto(slot),
                      onRemove: slot < _photos.length ? () => _removePhoto(slot) : null,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),

            // Mandatory responsibility declaration — must be accepted to book.
            InkWell(
              onTap: () => setState(() {
                _consent = !_consent;
                if (_consent) _error = null;
              }),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111A2E) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _consent
                        ? const Color(0xFF10B981)
                        : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _consent,
                        onChanged: (v) => setState(() {
                          _consent = v ?? false;
                          if (_consent) _error = null;
                        }),
                        activeColor: const Color(0xFF10B981),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Customer is solely responsible for parcel contents. Kranti Cabs, Company & Partner are not responsible for any illegal/prohibited items.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                // Disabled mid-upload (a photo still saving) and until the
                // sender accepts the mandatory responsibility declaration.
                onPressed: (_uploadingSlot != null || !_consent) ? null : _save,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.chevron_right, size: 18, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialChips extends StatelessWidget {
  final List<GoodsTypeModel> types;
  final String selected;
  final ValueChanged<String> onSelect;

  const _MaterialChips({
    required this.types,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: types
            .map((type) => _Chip(
                  label: type.name,
                  selected: selected.toLowerCase() == type.name.toLowerCase(),
                  onTap: () => onSelect(type.name),
                ))
            .toList(),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? const Color(0xFF1E293B) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected
                ? Colors.white
                : (isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
        ),
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final String? url;
  final File? preview;
  final bool uploading;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  const _PhotoSlot({
    required this.url,
    required this.preview,
    required this.uploading,
    required this.isDark,
    required this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final hasPhoto = preview != null || (url != null && url!.isNotEmpty);

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              onTap: uploading ? null : onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111C2E) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? _preview()
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 26,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add photo',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),

          if (uploading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0x99000000),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  ),
                ),
              ),
            ),

          if (onRemove != null && !uploading)
            Positioned(
              top: 6,
              right: 6,
              child: InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(14),
                child: const CircleAvatar(
                  radius: 13,
                  backgroundColor: Color(0xCC0F172A),
                  child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preview() {
    final file = preview;
    if (file != null) {
      return Image.file(file, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }

    return Image.network(
      url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => const Center(
        child: Icon(Icons.broken_image_outlined, size: 22, color: Color(0xFF94A3B8)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionLabel({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextField(
      controller: controller,
      maxLines: 1,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: isDark ? const Color(0xFF111C2E) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
      ),
    );
  }
}
