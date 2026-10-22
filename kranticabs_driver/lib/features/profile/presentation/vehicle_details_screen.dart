import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/document_template.dart';
import '../application/profile_providers.dart';

IconData _iconForVehicleType(String iconType) {
  switch (iconType) {
    case 'bike':
      return Icons.two_wheeler_outlined;
    case 'auto':
      return Icons.electric_rickshaw_outlined;
    default:
      return Icons.directions_car_outlined;
  }
}

String _labelForVehicleType(String iconType) {
  switch (iconType) {
    case 'bike':
      return 'Bike';
    case 'auto':
      return 'Auto';
    default:
      return 'Car';
  }
}

class VehicleDetailsScreen extends ConsumerStatefulWidget {
  const VehicleDetailsScreen({super.key});

  @override
  ConsumerState<VehicleDetailsScreen> createState() =>
      _VehicleDetailsScreenState();
}

class _VehicleDetailsScreenState extends ConsumerState<VehicleDetailsScreen> {
  late final TextEditingController _numberController;
  late final TextEditingController _colorController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final driver = ref.read(authProvider).driver;
    _numberController = TextEditingController(
      text: driver?.vehicleNumber ?? '',
    );
    _colorController = TextEditingController(text: driver?.vehicleColor ?? '');
  }

  @override
  void dispose() {
    _numberController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Re-verification required'),
        content: const Text(
          'Changing your vehicle number or color will reset your account to pending status until it is re-approved. You will not be able to go online until then.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateVehicle(
            vehicleNumber: _numberController.text.trim(),
            vehicleColor: _colorController.text.trim(),
          );
      await ref.read(authProvider.notifier).refresh();
      if (mounted) SnackbarUtils.success('Vehicle details updated');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The real catalog entries for every vehicle type the driver is enrolled
  /// in — a driver can pick more than one at onboarding (e.g. GKB, GKB
  /// Non-AC, GKB Airport AC) and gets ride requests for all of them.
  ///
  /// Resolved by `vehicleTypeIds` against the same admin catalog the
  /// registration picker itself reads from — those ids are what dispatch
  /// actually matches on.
  List<VehicleTypeOption> _resolveVehicleTypes(
    WidgetRef ref,
    List<String> vehicleTypeIds,
  ) {
    if (vehicleTypeIds.isEmpty) return const [];
    final catalog = ref.watch(vehicleTypeCatalogProvider).valueOrNull;
    if (catalog == null) return const [];
    return vehicleTypeIds
        .map((id) {
          for (final option in catalog) {
            if (option.id == id) return option;
          }
          return null;
        })
        .whereType<VehicleTypeOption>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final driver = ref.watch(authProvider).driver;
    final selectedVehicles = _resolveVehicleTypes(
      ref,
      driver?.vehicleTypeIds ?? const [],
    );
    // The catalog lookup came back empty (still loading, offline, or an id
    // no longer exists) — fall back to whatever flat name the backend last
    // sent, so the section is never blank just because the catalog request
    // is slow or failed.
    final fallbackName = driver?.vehicleType;

    return Scaffold(
      appBar: const CustomAppBar(title: 'Vehicle Details'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Editing vehicle number or color will require re-approval before you can go online again.',
                    style: TextStyle(
                      color: AppColors.warning,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Your Selected Vehicles',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'You receive ride requests for every vehicle type below.',
            style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (selectedVehicles.isNotEmpty)
            ...selectedVehicles.map(
              (option) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SelectedVehicleTile(option: option),
              ),
            )
          else if (fallbackName != null && fallbackName.isNotEmpty)
            _SelectedVehicleTile(
              option: VehicleTypeOption(
                id: '',
                name: fallbackName,
                iconType: fallbackName.toLowerCase(),
                transportType: 'taxi',
              ),
            )
          else
            const Text(
              'No vehicle type on file',
              style: TextStyle(color: AppColors.lightTextSecondary),
            ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _numberController,
            label: 'Vehicle number',
            hint: 'DL1AB2345',
            textCapitalization: TextCapitalization.characters,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _colorController,
            label: 'Vehicle color',
            hint: 'White',
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Save Changes',
            onPressed: _save,
            loading: _saving,
          ),
        ],
      ),
    );
  }
}

class _SelectedVehicleTile extends StatelessWidget {
  final VehicleTypeOption option;

  const _SelectedVehicleTile({required this.option});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForVehicleType(option.iconType),
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _labelForVehicleType(option.iconType),
                  style: const TextStyle(
                    color: AppColors.lightTextSecondary,
                    fontSize: 12,
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
