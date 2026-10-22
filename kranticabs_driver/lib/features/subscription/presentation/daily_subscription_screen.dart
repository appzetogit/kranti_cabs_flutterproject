import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/services/razorpay_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/ist_time.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/application/auth_providers.dart';
import '../../earnings/application/earnings_providers.dart';
import '../application/subscription_providers.dart';
import '../data/subscription_model.dart';

class DailySubscriptionScreen extends ConsumerStatefulWidget {
  const DailySubscriptionScreen({super.key});

  @override
  ConsumerState<DailySubscriptionScreen> createState() => _DailySubscriptionScreenState();
}

class _DailySubscriptionScreenState extends ConsumerState<DailySubscriptionScreen>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _selectedPlanId;
  Timer? _tickTimer;
  bool _flippedExpiredThisCycle = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Drives the "expires in Xh Ym" countdown and catches a pass lapsing
    // while this screen sits open across the 6 AM cutover.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(subscriptionStatusProvider.notifier).refresh();
    }
  }

  /// Shown once ever, the first time this screen sees a pass paid with the
  /// joining bonus - a plain wallet debit wouldn't otherwise tell the driver
  /// why a pass appeared without them buying one.
  Future<void> _maybeShowBonusDialog(SubscriptionStatus status) async {
    final sub = status.subscription;
    if (sub == null || sub.paymentMethod != 'bonus') return;

    final prefs = await SharedPreferences.getInstance();
    final seenKey = 'bonus_subscription_seen_${sub.id}';
    if (prefs.getBool(seenKey) == true) return;
    await prefs.setBool(seenKey, true);

    final days = (sub.startsAt != null && sub.expiresAt != null)
        ? sub.expiresAt!.difference(sub.startsAt!).inHours ~/ 24
        : null;
    final daysText = days != null && days > 0 ? '$days-day ' : '';

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subscription activated'),
        content: Text(
          'Your $daysText${sub.planName.isEmpty ? "Daily Subscription" : sub.planName} is already active - '
          'paid using your ₹${sub.amount.toStringAsFixed(0)} joining bonus. '
          'From your next pass onward, you\'ll pay by wallet or UPI as usual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _onTick() {
    if (!mounted) return;
    final async = ref.read(subscriptionStatusProvider);
    final status = async.valueOrNull;
    if (status != null && status.isActive && status.expiresAt != null) {
      if (DateTime.now().toUtc().isAfter(status.expiresAt!) && !_flippedExpiredThisCycle) {
        _flippedExpiredThisCycle = true;
        // The API is the source of truth for the cutover, not a local
        // clock check — re-fetch rather than flipping the badge ourselves.
        ref.read(subscriptionStatusProvider.notifier).refresh();
        return;
      }
    }
    setState(() {});
  }

  Future<void> _purchase(SubscriptionPlan plan, String paymentMethod) async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(subscriptionRepositoryProvider)
          .purchase(planId: plan.id, paymentMethod: paymentMethod);
      final refreshed = result.status;
      if (refreshed != null) {
        ref.read(subscriptionStatusProvider.notifier).applyStatus(refreshed);
      } else {
        await ref.read(subscriptionStatusProvider.notifier).refresh();
      }
      _flippedExpiredThisCycle = false;
      if (mounted) SnackbarUtils.success('Daily pass activated');
    } on ApiException catch (e) {
      final message = e.message.toLowerCase();
      if (e.statusCode == 409 || message.contains('already active')) {
        await ref.read(subscriptionStatusProvider.notifier).refresh();
        if (mounted) SnackbarUtils.info('You already have an active pass for today');
      } else if (e.statusCode == 400 &&
          (message.contains('not enough') ||
              message.contains('insufficient') ||
              message.contains('balance'))) {
        if (mounted) {
          SnackbarUtils.error('Not enough wallet balance');
          unawaited(_payByGateway(plan));
        }
        return;
      } else if (e.statusCode == 400) {
        // Subscriptions/payment method got toggled off server-side mid-flow.
        await ref.read(subscriptionStatusProvider.notifier).refresh();
        if (mounted) SnackbarUtils.info('Subscription settings changed — please try again');
      } else {
        if (mounted) SnackbarUtils.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// UPI/card path: top up the wallet shortfall through the existing
  /// verified Razorpay flow, then settle the pass as a wallet purchase.
  /// Intentionally not using `paymentMethod: "razorpay"` on `/purchase` —
  /// that creates an unpaid pass pending a gateway webhook, a second,
  /// unverified payment path this app doesn't need.
  Future<void> _payByGateway(SubscriptionPlan plan) async {
    setState(() => _busy = true);
    try {
      final wallet = await ref.read(earningsRepositoryProvider).getWallet();
      final shortfall = plan.amount - wallet.wallet.balance;

      if (shortfall <= 0) {
        await _purchase(plan, 'wallet');
        return;
      }

      final order = await ref.read(earningsRepositoryProvider).createTopupOrder(shortfall);
      final driver = ref.read(authProvider).driver;

      ref.read(razorpayServiceProvider).open(
            request: RazorpayCheckoutRequest(
              keyId: order.keyId,
              orderId: order.orderId,
              amount: shortfall,
              name: 'Daily pass top-up',
              description: plan.name,
              contact: driver?.phone,
              email: driver?.email,
            ),
            onSuccess: (PaymentSuccessResponse response) async {
              try {
                await ref.read(earningsRepositoryProvider).verifyTopupPayment({
                  'razorpay_payment_id': response.paymentId,
                  'razorpay_order_id': response.orderId,
                  'razorpay_signature': response.signature,
                });
                ref.invalidate(walletSnapshotProvider);
                await _purchase(plan, 'wallet');
              } on ApiException catch (e) {
                if (mounted) {
                  SnackbarUtils.error('Payment taken but not confirmed: ${e.message}');
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            onError: (PaymentFailureResponse response) {
              if (mounted) {
                SnackbarUtils.error(response.message ?? 'Payment failed or was cancelled');
                setState(() => _busy = false);
              }
            },
          );
    } on ApiException catch (e) {
      if (mounted) {
        SnackbarUtils.error(e.message);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(subscriptionStatusProvider, (previous, next) {
      next.whenData(_maybeShowBonusDialog);
    });
    final async = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Daily Subscription'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your subscription', style: TextStyle(color: AppColors.lightTextSecondary)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(subscriptionStatusProvider.notifier).refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (status) {
          if (!status.enabled) {
            // Menu entry is hidden when disabled; this only covers a
            // stale deep link / back-navigation into the route.
            return const Center(
              child: Text('Daily subscription is not available here', style: TextStyle(color: AppColors.lightTextSecondary)),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(subscriptionStatusProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (status.isActive)
                  _ActiveCard(status: status)
                else
                  _ExpiredCard(
                    status: status,
                    selectedPlanId: _selectedPlanId,
                    onSelectPlan: (id) => setState(() => _selectedPlanId = id),
                    busy: _busy,
                    onPayWallet: (plan) => _purchase(plan, 'wallet'),
                    onPayGateway: _payByGateway,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ActiveCard extends StatelessWidget {
  final SubscriptionStatus status;

  const _ActiveCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final expiresAt = status.expiresAt;
    final sub = status.subscription;
    final now = DateTime.now().toUtc();
    final remaining = expiresAt != null && expiresAt.isAfter(now) ? expiresAt.difference(now) : Duration.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: AppColors.earningsGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                sub?.planName ?? 'Daily Pass',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              if (expiresAt != null)
                Text(
                  'Valid until ${DateFormat('h:mm a, d MMM').format(toIst(expiresAt))}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              if (expiresAt != null && remaining > Duration.zero) ...[
                const SizedBox(height: 4),
                Text(
                  'Expires in ${_formatRemaining(remaining)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.lightBorder),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What this gives you', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              SizedBox(height: 10),
              _BenefitRow(text: 'No commission on trips today'),
              SizedBox(height: 6),
              _BenefitRow(text: 'No wallet minimum until the pass expires'),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatRemaining(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours <= 0) return '$minutes m';
    return '${hours}h ${minutes}m';
  }
}

class _BenefitRow extends StatelessWidget {
  final String text;

  const _BenefitRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13))),
      ],
    );
  }
}

class _ExpiredCard extends StatelessWidget {
  final SubscriptionStatus status;
  final String? selectedPlanId;
  final ValueChanged<String> onSelectPlan;
  final bool busy;
  final void Function(SubscriptionPlan plan) onPayWallet;
  final void Function(SubscriptionPlan plan) onPayGateway;

  const _ExpiredCard({
    required this.status,
    required this.selectedPlanId,
    required this.onSelectPlan,
    required this.busy,
    required this.onPayWallet,
    required this.onPayGateway,
  });

  @override
  Widget build(BuildContext context) {
    final plans = status.plans;
    final selected = plans.isEmpty
        ? null
        : plans.firstWhere((p) => p.id == selectedPlanId, orElse: () => plans.first);
    final canWallet = status.paymentMethods.contains('wallet');
    final canGateway = status.paymentMethods.contains('gateway');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.lightTextSecondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Expired',
                style: TextStyle(color: AppColors.lightTextSecondary, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (status.blocksRidesWhenExpired)
          _WarningBanner(text: 'You will not receive ride requests until you subscribe.')
        else
          _WarningBanner(
            text: 'Without a pass, commission applies to each trip as usual.',
            color: AppColors.info,
          ),
        const SizedBox(height: 16),
        if (plans.isEmpty)
          const Text('No plan is available right now.', style: TextStyle(color: AppColors.lightTextSecondary))
        else ...[
          Text(
            plans.length > 1 ? 'Choose a plan' : 'Your plan',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          ...plans.map((plan) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PlanCard(
                  plan: plan,
                  selected: plan.id == selected?.id,
                  selectable: plans.length > 1,
                  onTap: () => onSelectPlan(plan.id),
                ),
              )),
          const SizedBox(height: 8),
          if (selected != null) ...[
            if (canWallet)
              PrimaryButton(
                label: 'Pay ₹${selected.amount.toStringAsFixed(0)} by Wallet',
                loading: busy,
                onPressed: busy ? null : () => onPayWallet(selected),
              ),
            if (canWallet && canGateway) const SizedBox(height: 10),
            if (canGateway)
              PrimaryButton(
                label: 'Pay ₹${selected.amount.toStringAsFixed(0)} by UPI / Card',
                color: AppColors.accentDark,
                loading: busy,
                onPressed: busy ? null : () => onPayGateway(selected),
              ),
          ],
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionPlan plan;
  final bool selected;
  final bool selectable;
  final VoidCallback onTap;

  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.selectable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selectable ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : AppColors.lightBorder, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            if (selectable) ...[
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.lightTextSecondary,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                  if (plan.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(plan.description, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Text(
              '₹${plan.amount.toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  final Color color;

  const _WarningBanner({required this.text, this.color = AppColors.warning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
