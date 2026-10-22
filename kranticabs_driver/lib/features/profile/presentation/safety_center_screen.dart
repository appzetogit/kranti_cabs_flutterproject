import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/loading_widget.dart';
import '../../../shared/widgets/primary_button.dart';
import '../application/profile_providers.dart';
import '../data/emergency_contact.dart';

class SafetyCenterScreen extends ConsumerStatefulWidget {
  const SafetyCenterScreen({super.key});

  @override
  ConsumerState<SafetyCenterScreen> createState() => _SafetyCenterScreenState();
}

class _SafetyCenterScreenState extends ConsumerState<SafetyCenterScreen> {
  bool _sosSending = false;

  Future<void> _triggerSos() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send SOS alert?'),
        content: const Text(
          'This will immediately alert your emergency contacts and support with your current location.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send SOS', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _sosSending = true);
    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      await ref.read(profileRepositoryProvider).triggerSos(
            lat: position.latitude,
            lng: position.longitude,
          );
      if (mounted) SnackbarUtils.success('SOS alert sent');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } catch (_) {
      if (mounted) SnackbarUtils.error('Could not get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _sosSending = false);
    }
  }

  Future<void> _addContact() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add emergency contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: nameController, label: 'Name', hint: 'Contact name'),
            const SizedBox(height: 12),
            AppTextField(
              controller: phoneController,
              label: 'Phone',
              hint: '9876543210',
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (saved != true) return;
    if (nameController.text.trim().isEmpty || phoneController.text.trim().isEmpty) return;

    try {
      await ref.read(emergencyContactsProvider.notifier).add(
            nameController.text.trim(),
            phoneController.text.trim(),
          );
      if (mounted) SnackbarUtils.success('Emergency contact added');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    }
  }

  Future<void> _removeContact(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact'),
        content: Text('Remove ${contact.name} from your emergency contacts?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(emergencyContactsProvider.notifier).remove(contact.id);
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsState = ref.watch(emergencyContactsProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Safety Center'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Icon(Icons.shield_outlined, color: AppColors.error, size: 36),
                const SizedBox(height: 10),
                const Text(
                  'In an emergency, tap the button below to alert your emergency contacts and support with your live location.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: 'SOS - Send Alert',
                  onPressed: _triggerSos,
                  loading: _sosSending,
                  color: AppColors.error,
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Emergency Contacts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              TextButton.icon(
                onPressed: _addContact,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          contactsState.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: LoadingWidget(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                icon: Icons.error_outline,
                title: 'Could not load contacts',
                actionLabel: 'Retry',
                onAction: () => ref.read(emergencyContactsProvider.notifier).load(),
              ),
            ),
            data: (contacts) {
              if (contacts.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                    icon: Icons.contact_phone_outlined,
                    title: 'No emergency contacts yet',
                    subtitle: 'Add trusted contacts who will be alerted in an emergency.',
                  ),
                );
              }
              return Column(
                children: contacts
                    .map(
                      (c) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.lightBorder),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              child: const Icon(Icons.person, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                  Text(c.phone, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: () => _removeContact(c),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
