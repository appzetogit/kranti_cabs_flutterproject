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
import '../data/support_models.dart';

class RaiseTicketScreen extends ConsumerStatefulWidget {
  const RaiseTicketScreen({super.key});

  @override
  ConsumerState<RaiseTicketScreen> createState() => _RaiseTicketScreenState();
}

class _RaiseTicketScreenState extends ConsumerState<RaiseTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  SupportTitle? _selectedTitle;
  bool _busy = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final ticket = await ref.read(supportRepositoryProvider).createTicket(
            titleId: _selectedTitle?.id,
            title: _selectedTitle?.title,
            message: _messageController.text.trim(),
          );
      ref.invalidate(myTicketsProvider);
      if (mounted) {
        SnackbarUtils.success('Ticket raised successfully');
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
    final titlesAsync = ref.watch(supportTitlesProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Raise a Ticket'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            titlesAsync.when(
              data: (titles) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.lightBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<SupportTitle>(
                    isExpanded: true,
                    hint: const Text('Select a category (optional)'),
                    value: _selectedTitle,
                    items: titles
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.title)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedTitle = value),
                  ),
                ),
              ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (error, stack) => const Text(
                'Could not load categories — you can still submit a general ticket',
                style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            AppTextField(
              controller: _messageController,
              label: 'Message',
              hint: 'Describe your issue in detail...',
              maxLines: 6,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? 'Please describe your issue' : null,
            ),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Submit Ticket', onPressed: _submit, loading: _busy),
          ],
        ),
      ),
    );
  }
}
