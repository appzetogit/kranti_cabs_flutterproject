import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/registration_step_progress_bar.dart';
import '../data/document_template.dart';
import '../application/signup_providers.dart';

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

/// What the driver signs up to run. Multi-select — a driver can do city rides
/// and airport runs on the same vehicle.
///
/// The first value of each pair goes to the backend and must match an entry in
/// `ALLOWED_SERVICE_CATEGORIES` there; anything else is dropped on save and the
/// choice silently disappears.
const _serviceCategories = [
  ('taxi', 'City Rides'),
  ('outstation', 'Outstation'),
  ('delivery', 'Delivery'),
  ('airport', 'Kranti Airport'),
];

/// Which side of the vehicle catalog each service category draws from.
///
/// A driver runs one vehicle, so ticking City Rides and Delivery together
/// widens the picker to both sides rather than leaving it empty.
const _categoryTransportTypes = {
  'taxi': 'taxi',
  'outstation': 'taxi',
  'airport': 'taxi',
  'delivery': 'delivery',
};

const _fuelTypes = ['Petrol', 'Diesel', 'CNG', 'Electric', 'Hybrid'];

class VehicleInfoScreen extends ConsumerStatefulWidget {
  const VehicleInfoScreen({super.key});

  @override
  ConsumerState<VehicleInfoScreen> createState() => _VehicleInfoScreenState();
}

class _VehicleInfoScreenState extends ConsumerState<VehicleInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _rcController = TextEditingController();
  final _makeController = TextEditingController();
  final _modelController = TextEditingController();
  final _yearController = TextEditingController();
  final _numberController = TextEditingController();
  final _colorController = TextEditingController();

  // Must be real catalog ids: dispatch matches drivers against the vehicle
  // type the rider booked, so a placeholder string leaves the driver
  // unmatched. A driver can enroll in more than one tier — e.g. both Kranti Cab
  // AC and Kranti Cab Non-AC on the same car — so any of these is enough to
  // receive a matching ride.
  final Set<String> _vehicleTypeIds = {};
  final Set<String> _categories = {'taxi'};

  /// Only the tiers that can actually serve the ticked categories.
  ///
  /// Registering on a tier the rider app never books for that service is the
  /// commonest way a driver ends up receiving nothing, so the wrong options
  /// are not offered at all.
  List<VehicleTypeOption> get _serviceFilteredVehicleTypes {
    final allowed = _categories
        .map((category) => _categoryTransportTypes[category])
        .whereType<String>()
        .toSet();

    if (allowed.isEmpty) return _vehicleTypes;

    return _vehicleTypes
        .where((option) => allowed.contains(option.transportType))
        .toList(growable: false);
  }

  /// Every vehicle family (bike / auto / car ...) the admin has set up, in a
  /// fixed friendly order.
  ///
  /// Deliberately not narrowed by the ticked services. The admin files bike
  /// tiers under delivery (there is no bike taxi), so narrowing by "City
  /// Rides" hid Bike altogether and a bike rider could not register.
  List<String> get _availableVehicleCategories {
    const order = ['bike', 'auto', 'car'];
    final found = _vehicleTypes
        .map((option) => option.iconType)
        .where((value) => value.isNotEmpty)
        .toSet();
    final sorted = order.where(found.contains).toList();
    sorted.addAll(found.where((value) => !order.contains(value)));
    return sorted;
  }

  /// The family the driver picked first; the tiers below are only those in it.
  String? _vehicleCategory;

  /// The tiers of the chosen family. Those that serve the ticked services come
  /// first-class; when the family has none for them (Bike under City Rides),
  /// all of the family's tiers are offered instead of an empty list.
  List<VehicleTypeOption> get _selectableVehicleTypes {
    if (_vehicleCategory == null) return _serviceFilteredVehicleTypes;

    final inFamily = _vehicleTypes
        .where((option) => option.iconType == _vehicleCategory)
        .toList(growable: false);
    final serving = _serviceFilteredVehicleTypes
        .where((option) => option.iconType == _vehicleCategory)
        .toList(growable: false);

    return serving.isNotEmpty ? serving : inFamily;
  }

  /// Keeps the service categories consistent with the chosen tiers: a
  /// delivery-side tier registered without the Delivery service would match no
  /// booking at all, and likewise a taxi-side tier without any ride service.
  void _alignServicesToSelection() {
    final chosen = _vehicleTypes.where((option) => _vehicleTypeIds.contains(option.id));
    final hasDelivery = chosen.any((option) => option.transportType == 'delivery');
    final hasTaxi = chosen.any((option) => option.transportType != 'delivery');

    if (hasDelivery) _categories.add('delivery');

    final servesTaxi = _categories.any((category) => _categoryTransportTypes[category] == 'taxi');
    if (hasTaxi && !servesTaxi) _categories.add('taxi');
  }

  /// Drops selections the current categories no longer allow, falling back to
  /// the first that is if that empties the set entirely. Without this,
  /// un-ticking Delivery would leave a delivery-only vehicle silently
  /// selected and saved.
  void _syncVehicleSelection() {
    final categories = _availableVehicleCategories;
    if (!categories.contains(_vehicleCategory)) {
      _vehicleCategory = categories.isNotEmpty ? categories.first : null;
    }
    final selectable = _selectableVehicleTypes;
    final selectableIds = selectable.map((option) => option.id).toSet();

    if (selectable.isEmpty) {
      _vehicleTypeIds.clear();
      return;
    }

    _vehicleTypeIds.retainAll(selectableIds);
    if (_vehicleTypeIds.isEmpty) {
      _vehicleTypeIds.add(selectable.first.id);
    }

    _alignServicesToSelection();
  }

  String? _fuelType;
  String? _locationId;
  List<ServiceLocationOption> _locations = [];
  List<VehicleTypeOption> _vehicleTypes = [];
  bool _loadingOptions = true;
  bool _submitting = false;

  static const _standardFieldKeys = {
    'locationId',
    'serviceCategories',
    'vehicleTypeId',
    'make',
    'model',
    'year',
    'number',
    'color',
    'companyName',
    'companyAddress',
    'city',
    'postalCode',
    'taxNumber',
  };

  VehicleFieldTemplate? _fuelFieldTemplate;
  List<VehicleFieldTemplate> _extraRequiredFields = [];
  final Map<String, String?> _extraFieldValues = {};
  final Map<String, TextEditingController> _extraFieldControllers = {};

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final results = await Future.wait([
        ref.read(signupProvider.notifier).getSignupOptions(),
        ref.read(signupProvider.notifier).getVehicleFieldTemplates(),
        ref.read(signupProvider.notifier).getVehicleTypes(),
      ]);
      if (!mounted) return;
      final locations = results[0] as List<ServiceLocationOption>;
      final templates = results[1] as List<VehicleFieldTemplate>;
      final vehicleTypes = results[2] as List<VehicleTypeOption>;
      final requiredCustomFields = templates.where(
        (t) => t.isRequired && !_standardFieldKeys.contains(t.fieldKey),
      );
      VehicleFieldTemplate? fuelTemplate;
      final extras = <VehicleFieldTemplate>[];
      for (final template in requiredCustomFields) {
        final looksLikeFuel =
            template.fieldKey.toLowerCase().contains('fuel') ||
            template.name.toLowerCase().contains('fuel');
        if (looksLikeFuel && fuelTemplate == null) {
          fuelTemplate = template;
        } else {
          extras.add(template);
          if (template.options.isEmpty) {
            _extraFieldControllers[template.fieldKey] = TextEditingController();
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _locations = locations;
        _locationId = locations.isNotEmpty ? locations.first.id : null;
        _vehicleTypes = vehicleTypes;
        _syncVehicleSelection();
        _fuelFieldTemplate = fuelTemplate;
        _extraRequiredFields = extras;
        _loadingOptions = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_locationId == null || _locationId!.isEmpty) {
      SnackbarUtils.error('Select your operating city');
      return;
    }
    if (_vehicleTypeIds.isEmpty) {
      SnackbarUtils.error('Select your vehicle type');
      return;
    }
    setState(() => _submitting = true);
    try {
      final customFields = <String, dynamic>{
        if (_fuelFieldTemplate != null)
          _fuelFieldTemplate!.fieldKey: _fuelType ?? '',
        for (final field in _extraRequiredFields)
          field.fieldKey: field.options.isNotEmpty
              ? (_extraFieldValues[field.fieldKey] ?? '')
              : _extraFieldControllers[field.fieldKey]!.text.trim(),
      };
      await ref
          .read(signupProvider.notifier)
          .saveVehicle(
            locationId: _locationId!,
            serviceCategories: _categories.toList(),
            vehicleTypeIds: _vehicleTypeIds.toList(),
            rcNumber: _rcController.text.trim(),
            make: _makeController.text.trim(),
            model: _modelController.text.trim(),
            year: _yearController.text.trim(),
            number: _numberController.text.trim(),
            color: _colorController.text.trim(),
            fuelType: _fuelType!,
            customFields: customFields,
          );
      if (!mounted) return;
      context.push('/documents-upload');
    } on ApiException catch (e) {
      SnackbarUtils.error(e.message);
    } catch (_) {
      SnackbarUtils.error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _rcController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _yearController.dispose();
    _numberController.dispose();
    _colorController.dispose();
    for (final controller in _extraFieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _extraFieldWidget(VehicleFieldTemplate field) {
    if (field.options.isNotEmpty) {
      return DropdownButtonFormField<String>(
        initialValue: _extraFieldValues[field.fieldKey],
        dropdownColor: const Color(0xFF222222),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        hint: Text(
          'Select ${field.name}',
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        items: field.options
            .map(
              (o) => DropdownMenuItem(
                value: o,
                child: Text(o, style: const TextStyle(color: Colors.white)),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => _extraFieldValues[field.fieldKey] = v),
        validator: (v) => Validators.required(v, field: field.name),
      );
    }
    return AppTextField(
      controller: _extraFieldControllers[field.fieldKey],
      label: field.name,
      hint: field.name,
      validator: (v) => Validators.required(v, field: field.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Vehicle Details', showBack: true),
      bottomNavigationBar: const SafeArea(
        child: RegistrationProgressBar(currentStep: 2),
      ),
      body: SafeArea(
        child: _loadingOptions
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          'Step 2 of 3',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_availableVehicleCategories.isNotEmpty) ...[
                        Text(
                          'Vehicle Category',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _availableVehicleCategories.map((category) {
                            final selected = _vehicleCategory == category;
                            return ChoiceChip(
                              avatar: Icon(
                                _iconForVehicleType(category),
                                size: 18,
                                color: selected
                                    ? const Color(0xFF11191D)
                                    : Colors.white70,
                              ),
                              label: Text(
                                category[0].toUpperCase() +
                                    category.substring(1),
                                style: TextStyle(
                                  color: selected
                                      ? const Color(0xFF11191D)
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              selected: selected,
                              onSelected: (_) => setState(() {
                                _vehicleCategory = category;
                                // Tiers belong to one family; picking another
                                // starts that family's selection afresh.
                                _vehicleTypeIds.clear();
                                _syncVehicleSelection();
                              }),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                        'Vehicle Type',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 10),
                      if (_selectableVehicleTypes.isEmpty)
                        Text(
                          _vehicleTypes.isEmpty
                              ? 'No vehicle types are available right now. Please try again later.'
                              : 'No vehicle is set up for the services you picked yet. '
                                    'Choose a different service category, or contact support.',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 10.0;
                            final selectable = _selectableVehicleTypes;
                            final columns = selectable.length < 3
                                ? selectable.length
                                : 3;
                            final width =
                                (constraints.maxWidth -
                                    (spacing * (columns - 1))) /
                                columns;
                            return Wrap(
                              spacing: spacing,
                              runSpacing: spacing,
                              children: selectable
                                  .map(
                                    (option) => SizedBox(
                                      width: width,
                                      child: _vehicleTypeChip(option),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                      const SizedBox(height: 20),
                      Text(
                        'Service Category',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: _serviceCategories.map((cat) {
                          final selected = _categories.contains(cat.$1);
                          return FilterChip(
                            label: Text(
                              cat.$2,
                              style: TextStyle(
                                color: selected
                                    ? const Color(0xFF11191D)
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _categories.add(cat.$1);
                                } else if (_categories.length > 1) {
                                  _categories.remove(cat.$1);
                                }
                                // The picker narrows with the categories, so
                                // a now-disallowed vehicle must not stay
                                // selected.
                                _syncVehicleSelection();
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      if (_locations.isNotEmpty) ...[
                        Text(
                          'Operating City',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _locationId,
                          dropdownColor: const Color(0xFF222222),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          items: _locations
                              .map(
                                (loc) => DropdownMenuItem(
                                  value: loc.id,
                                  child: Text(
                                    loc.name,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => _locationId = v),
                        ),
                        const SizedBox(height: 20),
                      ],
                      AppTextField(
                        controller: _rcController,
                        label: 'RC Number',
                        hint: 'DL01AB1234',
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) =>
                            Validators.required(v, field: 'RC number'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _makeController,
                              label: 'Brand / Make',
                              hint: 'Maruti',
                              validator: (v) =>
                                  Validators.required(v, field: 'Make'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _modelController,
                              label: 'Model',
                              hint: 'Swift Dzire',
                              validator: (v) =>
                                  Validators.required(v, field: 'Model'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _yearController,
                              label: 'Year',
                              hint: '2022',
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              validator: (v) =>
                                  Validators.required(v, field: 'Year'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _colorController,
                              label: 'Color',
                              hint: 'White',
                              validator: (v) =>
                                  Validators.required(v, field: 'Color'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Fuel Type',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _fuelType,
                        dropdownColor: const Color(0xFF222222),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        hint: const Text(
                          'Select fuel type',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                        items: _fuelTypes
                            .map(
                              (f) => DropdownMenuItem(
                                value: f,
                                child: Text(
                                  f,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _fuelType = v),
                        validator: (v) =>
                            Validators.required(v, field: 'Fuel type'),
                      ),
                      const SizedBox(height: 16),
                      for (final field in _extraRequiredFields) ...[
                        Text(
                          field.name,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        _extraFieldWidget(field),
                        const SizedBox(height: 16),
                      ],
                      AppTextField(
                        controller: _numberController,
                        label: 'Vehicle Number',
                        hint: 'DL1AB2345',
                        textCapitalization: TextCapitalization.characters,
                        validator: Validators.vehicleNumber,
                      ),
                      const SizedBox(height: 32),
                      PrimaryButton(
                        label: 'Continue',
                        onPressed: _submit,
                        loading: _submitting,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _vehicleTypeChip(VehicleTypeOption option) {
    final selected = _vehicleTypeIds.contains(option.id);
    final label = option.name;
    final icon = _iconForVehicleType(option.iconType);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          // At least one vehicle type must stay selected.
          if (_vehicleTypeIds.length > 1) _vehicleTypeIds.remove(option.id);
        } else {
          _vehicleTypeIds.add(option.id);
        }
        _alignServicesToSelection();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white70,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
