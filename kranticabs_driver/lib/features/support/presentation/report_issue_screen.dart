import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/support_providers.dart';

const _issueReasons = [
  'Fare related issue',
  'Passenger behaviour',
  'App not working properly',
  'Trip cancellation issue',
  'Payment not received',
  'Other',
];

class ReportIssueScreen extends ConsumerStatefulWidget {
  final String? tripId;

  const ReportIssueScreen({super.key, this.tripId});

  @override
  ConsumerState<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends ConsumerState<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  String _reason = _issueReasons.first;
  bool _busy = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final buffer = StringBuffer();
    if (widget.tripId != null) buffer.writeln('Trip ID: ${widget.tripId}');
    buffer.write(_messageController.text.trim());
    try {
      final ticket = await ref.read(supportRepositoryProvider).createTicket(
            title: _reason,
            message: buffer.toString(),
          );
      ref.invalidate(myTicketsProvider);
      if (mounted) {
        SnackbarUtils.success('Issue reported successfully');
        context.pushReplacement('/chat-support', extra: ticket.ticketCode);
      }
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Report an Issue'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('What went wrong?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.lightBorder),
                borderRadius: BorderRadius.circular(14),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _reason,
                  items: _issueReasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (value) => setState(() => _reason = value ?? _reason),
                ),
              ),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _messageController,
              label: 'Details',
              hint: 'Tell us more about the issue...',
              maxLines: 6,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Please describe the issue' : null,
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Submit Report', onPressed: _submit, loading: _busy),
          ],
        ),
      ),
    );
  }
}
