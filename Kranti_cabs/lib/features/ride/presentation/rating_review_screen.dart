import '../../../core/constants/app_constants.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ride_completion_payment_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/review_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../application/ride_tracking_controller.dart';

class RatingReviewScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RatingReviewScreen({super.key, required this.rideId});

  @override
  ConsumerState<RatingReviewScreen> createState() => _RatingReviewScreenState();
}

class _RatingReviewScreenState extends ConsumerState<RatingReviewScreen> {
  int _rating = 4;
  double _selectedTip = 0.0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  final List<double> _tipOptions = [0, 10, 20, 50];

  @override
  void initState() {
    super.initState();
    // An `online` ride arrives here with the fare still uncollected — the
    // backend's complete-payment endpoints existed but nothing called them.
    WidgetsBinding.instance.addPostFrameCallback((_) => _collectFareIfDue());
  }

  Future<void> _collectFareIfDue() async {
    if (!AppConstants.onlinePaymentsEnabled) return;
    final ride = ref.read(rideTrackingControllerProvider(widget.rideId)).ride;
    if (ride == null) return;
    if ((ride.paymentMethod ?? 'cash').toLowerCase() != 'online') return;
    if (ride.fare <= 0) return;
    // Already settled (paid during the trip, or collected by the driver):
    // asking again would invite a second charge.
    if (ride.isFarePaid) return;

    await RideCompletionPaymentSheet.show(
      context,
      rideId: widget.rideId,
      amount: ride.fare,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final ratingSubmitted = _rating > 0 ? _rating : 5;
    final controller = ref.read(rideTrackingControllerProvider(widget.rideId).notifier);
    final success = await controller.submitReview(
      rating: ratingSubmitted,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      tipAmount: _selectedTip,
    );
    if (mounted) {
      setState(() => _submitting = false);
      if (success) {
        SnackbarUtils.success(context, 'Thank you for your feedback!');
        await ReviewService.requestReviewIfEligible(rating: ratingSubmitted);
        if (mounted) context.go('/home');
      } else {
        context.go('/home');
      }
    }
  }

  void _shareReceipt(dynamic ride, String driverName, double totalFare) {
    final dateStr = Formatters.date(ride?.completedAt ?? DateTime.now());
    final fareStr = totalFare.toStringAsFixed(2);
    final text = 'Trip Receipt\nDate: $dateStr\nDriver: $driverName\nFare: ₹$fareStr\nThank you for riding!';
    Share.share(text);
  }

  String _getRatingFeedbackText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Okay';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return 'Very Good';
    }
  }

  IconData _getVehicleIcon(String? vehicleType, String? serviceType) {
    final lower = '${vehicleType ?? ''} ${serviceType ?? ''}'.toLowerCase();
    if (lower.contains('bike') || lower.contains('moto') || lower.contains('two_wheeler') || lower.contains('2_wheeler') || lower.contains('scooter')) {
      return Icons.two_wheeler_rounded;
    } else if (lower.contains('auto') || lower.contains('rickshaw') || lower.contains('3_wheeler') || lower.contains('three_wheeler')) {
      return Icons.electric_rickshaw_rounded;
    } else if (lower.contains('parcel') || lower.contains('delivery') || lower.contains('truck')) {
      return Icons.local_shipping_rounded;
    } else {
      return Icons.directions_car_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ref.watch(rideTrackingControllerProvider(widget.rideId)).ride;

    final completedDate = ride?.completedAt ?? ride?.startedAt ?? ride?.scheduledAt ?? ride?.acceptedAt ?? DateTime.now();
    final driver = ride?.driver;
    final pickup = (ride?.pickupAddress.isNotEmpty == true)
        ? ride!.pickupAddress
        : ((ride?.stops.isNotEmpty == true) ? ride!.stops.first.address : 'Pickup Location');
    final drop = (ride?.dropAddress.isNotEmpty == true)
        ? ride!.dropAddress
        : ((ride != null && ride.stops.length > 1) ? ride.stops.last.address : 'Drop Location');
    final driverName = (driver?.name.isNotEmpty == true)
        ? driver!.name
        : 'Driver';
    final vehicleNo = (driver?.vehicleNumber.isNotEmpty == true)
        ? driver!.vehicleNumber
        : '';
    final vehicleType = (driver?.vehicleMake.isNotEmpty == true)
        ? driver!.vehicleMake
        : ((driver?.vehicleModel.isNotEmpty == true)
            ? driver!.vehicleModel
            : (ride?.vehicleType ?? ''));
    final vehicleLine = [vehicleNo, vehicleType].where((s) => s.isNotEmpty).join(' • ');
    final vehicleDisplay = vehicleLine.isNotEmpty ? vehicleLine : 'Vehicle Details';
    final driverRating = (driver?.rating != null && driver!.rating > 0)
        ? driver.rating.toStringAsFixed(1)
        : '5.0';
    final baseFare = (ride != null && ride.fare > 0)
        ? ride.fare
        : (ride?.baseFare ?? 0.0);
    final totalFare = baseFare + _selectedTip;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              // --- TOP CONFETTI & CHECKMARK HEADER ---
              const SizedBox(height: 12),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x3310B981),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'You have arrived!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Thanks for riding with us 👋',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // --- CARD 1: TRIP RECEIPT ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row with Date & Share
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 20,
                          color: Color(0xFFF97316),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Trip Receipt',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${Formatters.date(completedDate)} • ${Formatters.time(completedDate)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => _shareReceipt(ride, driverName, totalFare),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_outlined, size: 14, color: Color(0xFF0F172A)),
                                SizedBox(width: 5),
                                Text(
                                  'Share',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Driver Row (Avatar, Name, Vehicle, Rating, Bike graphic)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: (driver?.profileImage != null && driver!.profileImage.isNotEmpty)
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: driver.profileImage,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(Icons.person, color: Color(0xFF0F172A), size: 26),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  vehicleDisplay,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                                    const SizedBox(width: 3),
                                    Text(
                                      driverRating,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            _getVehicleIcon(vehicleType, ride?.serviceType),
                            size: 40,
                            color: const Color(0xFF0F172A),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pickup & Drop Timeline Sub-box
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pickup,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'PICKUP',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF15803D),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: 12,
                                child: VerticalDivider(
                                  color: Color(0xFFCBD5E1),
                                  thickness: 1.5,
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF97316),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  drop,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEDD5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'DROP',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFC2410C),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (ride != null && (ride.isParcel || ride.parcel.category.isNotEmpty)) ...[
                      const SizedBox(height: 16),
                      _UserParcelCard(parcel: ride.parcel),
                    ],
                    const SizedBox(height: 16),

                    // Base fare & Tip rows
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Base fare',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '₹${baseFare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tip',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          '₹${_selectedTip.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(color: Color(0xFFE2E8F0), thickness: 1),
                    ),

                    // Total Amount Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          '₹${totalFare.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primaryOrange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- CARD 2: TIP YOUR DRIVER ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tip your driver',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Thank your driver with a tip',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Horizontal Tip selector chips
                    Row(
                      children: [
                        ..._tipOptions.map((amount) {
                          final isSelected = _selectedTip == amount;
                          final label = amount == 0 ? 'No tip' : '₹${amount.toInt()}';
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InkWell(
                                onTap: () => setState(() => _selectedTip = amount),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFFFFEDD5) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primaryOrange : const Color(0xFFE2E8F0),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                      color: isSelected ? AppColors.primaryOrange : const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final val = await _showCustomTipDialog(context);
                              if (val != null) setState(() => _selectedTip = val);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: const Text(
                                'Other',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- CARD 3: RATING CARD ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'How was your trip with $driverName?',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 5 Star rating buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starIndex = index + 1;
                        final isFilled = _rating >= starIndex;
                        return InkWell(
                          onTap: () => setState(() => _rating = starIndex),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              isFilled ? Icons.star_rounded : Icons.star_border_rounded,
                              size: 40,
                              color: isFilled ? AppColors.primaryOrange : const Color(0xFFCBD5E1),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRatingFeedbackText(_rating),
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // --- BOTTOM PRIMARY BUTTON: DONE ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryOrange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<double?> _showCustomTipDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter custom tip amount'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'e.g. 30'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text.trim());
              Navigator.pop(context, val);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _UserParcelCard extends StatelessWidget {
  final dynamic parcel;

  const _UserParcelCard({required this.parcel});

  @override
  Widget build(BuildContext context) {
    final description = (parcel.description ?? '').toString().trim();
    final category = (parcel.category ?? '').toString().trim();
    final weight = (parcel.weight ?? '').toString().trim();
    final instructions = (parcel.instructions ?? '').toString().trim();
    final senderName = (parcel.senderName ?? '').toString().trim();
    final senderMobile = (parcel.senderMobile ?? '').toString().trim();
    final receiverName = (parcel.receiverName ?? '').toString().trim();
    final receiverMobile = (parcel.receiverMobile ?? '').toString().trim();

    final title = description.isNotEmpty ? description : category;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_rounded, size: 16, color: Color(0xFF0EA5E9)),
              SizedBox(width: 8),
              Text(
                'PARCEL DETAILS',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (title.isNotEmpty)
            _ParcelLine(icon: Icons.category_outlined, label: 'Contents', value: title),
          if (category.isNotEmpty && description.isNotEmpty)
            _ParcelLine(icon: Icons.label_outline_rounded, label: 'Type', value: category),
          if (weight.isNotEmpty)
            _ParcelLine(icon: Icons.scale_outlined, label: 'Weight', value: weight),
          if (instructions.isNotEmpty)
            _ParcelLine(
              icon: Icons.priority_high_rounded,
              label: 'Instructions',
              value: instructions,
              valueColor: const Color(0xFFD97706),
            ),
          if (senderName.isNotEmpty)
            _ParcelLine(
              icon: Icons.person_outline_rounded,
              label: 'Sender',
              value: senderMobile.isEmpty ? senderName : '$senderName · $senderMobile',
            ),
          if (receiverName.isNotEmpty)
            _ParcelLine(
              icon: Icons.where_to_vote_outlined,
              label: 'Receiver',
              value: receiverMobile.isEmpty ? receiverName : '$receiverName · $receiverMobile',
            ),
          if ((parcel.pickupProof != null && parcel.pickupProof.exists) ||
              (parcel.deliveryProof != null && parcel.deliveryProof.exists)) ...[
            const SizedBox(height: 8),
            const Text(
              'HANDOVER PROOF PHOTOS',
              style: TextStyle(
                fontSize: 9.5,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w900,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (parcel.pickupProof != null && parcel.pickupProof.exists)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ParcelThumb(url: parcel.pickupProof.url),
                        const SizedBox(height: 2),
                        const Text('Pickup', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                if (parcel.deliveryProof != null && parcel.deliveryProof.exists)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ParcelThumb(url: parcel.deliveryProof.url),
                      const SizedBox(height: 2),
                      const Text('Delivery', style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
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

class _ParcelLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _ParcelLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 8),
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: valueColor ?? const Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ParcelThumb extends StatelessWidget {
  final String url;
  const _ParcelThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, _) => const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
        errorWidget: (_, _, _) => const Icon(Icons.broken_image_outlined, size: 18, color: Color(0xFF94A3B8)),
      ),
    );
  }
}
