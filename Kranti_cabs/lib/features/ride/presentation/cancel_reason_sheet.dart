import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/ride_providers.dart';
import '../data/models/cancellation_reason_model.dart';

/// What the rider chose in the cancel sheet.
class CancelReasonResult {
  final String? reasonId;
  final String title;
  final String note;

  const CancelReasonResult({this.reasonId, required this.title, this.note = ''});
}

/// Per stage (`before_driver` / `after_driver`), refetched every time the sheet
/// opens because the admin can change the list at any time.
final _cancellationReasonsProvider =
    FutureProvider.autoDispose.family<List<CancellationReasonModel>, String>((ref, stage) {
  return ref.read(rideRepositoryProvider).getCancellationReasons(stage);
});

/// Always offered last, whatever the admin configured, and always needs text.
const _otherReason = CancellationReasonModel(id: 'other', title: 'Other', requiresNote: true);

/// Asks the rider why they are cancelling before the ride is cancelled.
///
/// The list is served by the backend and edited in the admin panel, so the
/// wording can change without an app release.
///
/// [hasDriver] picks the list: reasons for a ride still searching, or for one
/// a captain has already accepted.
///
/// Returns null if the rider backs out — the caller must treat that as "do not
/// cancel", not as "cancelled with no reason".
Future<CancelReasonResult?> showCancelReasonSheet(BuildContext context, {required bool hasDriver}) {
  return showModalBottomSheet<CancelReasonResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CancelReasonSheet(stage: hasDriver ? 'after_driver' : 'before_driver'),
  );
}

class _CancelReasonSheet extends ConsumerStatefulWidget {
  final String stage;
  const _CancelReasonSheet({required this.stage});

  @override
  ConsumerState<_CancelReasonSheet> createState() => _CancelReasonSheetState();
}

class _CancelReasonSheetState extends ConsumerState<_CancelReasonSheet> {
  CancellationReasonModel? _selected;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final selected = _selected;
    if (selected == null) return false;
    // A catch-all entry with an empty note tells nobody anything.
    if (selected.requiresNote && _noteController.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    final selected = _selected;
    if (selected == null) return;

    Navigator.of(context).pop(
      CancelReasonResult(
        reasonId: selected.id,
        // "Other" is sent as just its note.
        title: selected.id == 'other' ? '' : selected.title,
        note: _noteController.text.trim(),
      ),
    );
  }

  Widget _reasonList(List<CancellationReasonModel> fetched, bool isDark) {
    final reasons = [...fetched.where((r) => r.id != 'other'), _otherReason];
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      itemCount: reasons.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final reason = reasons[index];
        return _ReasonTile(
          title: reason.title,
          isSelected: _selected?.id == reason.id,
          isDark: isDark,
          onTap: () => setState(() => _selected = reason),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final reasonsAsync = ref.watch(_cancellationReasonsProvider(widget.stage));

    return Padding(
      // Lifts the sheet clear of the keyboard when the note field is focused.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why are you cancelling?',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This helps us improve. Frequent cancellations may affect your account.',
                    style: TextStyle(fontSize: 12.5, color: textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
            Flexible(
              child: reasonsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                // A failed or empty list must never block the cancel: Other stays.
                error: (_, _) => _reasonList(const [], isDark),
                data: (reasons) => _reasonList(reasons, isDark),
              ),
            ),
            if (_selected?.requiresNote == true)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(
                  controller: _noteController,
                  autofocus: true,
                  maxLength: 200,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 14, color: textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Tell us what happened',
                    counterText: '',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Keep ride',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textMuted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Cancel ride',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonTile extends StatelessWidget {
  final String title;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _ReasonTile({
    required this.title,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF334155) : const Color(0xFFFEF2F2))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFDC2626)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20,
              color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
