import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/snackbar_utils.dart';
import '../../../shared/widgets/custom_app_bar.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/earnings_providers.dart';
import '../data/incentive_model.dart';

class IncentivesScreen extends ConsumerStatefulWidget {
  const IncentivesScreen({super.key});

  @override
  ConsumerState<IncentivesScreen> createState() => _IncentivesScreenState();
}

class _IncentivesScreenState extends ConsumerState<IncentivesScreen> {
  String? _claimingKey;

  Future<void> _claim({required String rewardType, required String rewardKey}) async {
    setState(() => _claimingKey = rewardKey);
    try {
      await ref.read(earningsRepositoryProvider).claimIncentive(rewardType: rewardType, rewardKey: rewardKey);
      ref.invalidate(incentiveSnapshotProvider);
      ref.invalidate(walletSnapshotProvider);
      if (mounted) SnackbarUtils.success('Reward claimed');
    } on ApiException catch (e) {
      if (mounted) SnackbarUtils.error(e.message);
    } finally {
      if (mounted) setState(() => _claimingKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incentivesAsync = ref.watch(incentiveSnapshotProvider);

    return Scaffold(
      appBar: const CustomAppBar(title: 'Incentives & Bonuses'),
      body: incentivesAsync.when(
        data: (snapshot) {
          if (snapshot.milestones.isEmpty && snapshot.features.isEmpty) {
            return const EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No active incentive programs',
              subtitle: 'Check back later for new bonus opportunities',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(incentiveSnapshotProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.earningsGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _SummaryStat(label: 'Streak', value: '${snapshot.streakDays} days'),
                      _SummaryStat(label: 'This week', value: '${snapshot.currentWeekTrips} trips'),
                    ],
                  ),
                ),
                if (snapshot.milestones.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Milestones', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...snapshot.milestones.map(
                    (m) => _MilestoneCard(
                      milestone: m,
                      busy: _claimingKey == m.id,
                      onClaim: () => _claim(rewardType: 'milestone', rewardKey: m.id),
                    ),
                  ),
                ],
                if (snapshot.features.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Bonuses', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...snapshot.features.map(
                    (f) => _FeatureCard(
                      feature: f,
                      busy: _claimingKey == f.key,
                      onClaim: () => _claim(rewardType: 'feature', rewardKey: f.key),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const EmptyState(icon: Icons.error_outline, title: 'Could not load incentives'),
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final MilestoneModel milestone;
  final bool busy;
  final VoidCallback onClaim;

  const _MilestoneCard({required this.milestone, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(milestone.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Text(
                '₹${milestone.payoutAmount.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (milestone.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(milestone.notes, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: milestone.dayProgress,
              minHeight: 8,
              backgroundColor: AppColors.lightBorder,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${milestone.qualifyingDays}/${milestone.targetDays} active days · ${milestone.qualifyingWeeks}/${milestone.targetWeeks} weeks',
            style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _ClaimButton(
            isEligible: milestone.isEligible,
            isClaimed: milestone.isClaimed,
            busy: busy,
            onClaim: onClaim,
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final FeatureRewardModel feature;
  final bool busy;
  final VoidCallback onClaim;

  const _FeatureCard({required this.feature, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(feature.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Text(
                '₹${feature.rewardAmount.toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          if (feature.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(feature.description, style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: feature.progress,
              minHeight: 8,
              backgroundColor: AppColors.lightBorder,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${feature.currentValue.toStringAsFixed(0)}/${feature.targetValue.toStringAsFixed(0)} ${feature.unit}',
            style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _ClaimButton(
            isEligible: feature.isEligible,
            isClaimed: feature.isClaimed,
            busy: busy,
            onClaim: onClaim,
          ),
        ],
      ),
    );
  }
}

class _ClaimButton extends StatelessWidget {
  final bool isEligible;
  final bool isClaimed;
  final bool busy;
  final VoidCallback onClaim;

  const _ClaimButton({
    required this.isEligible,
    required this.isClaimed,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    if (isClaimed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: const Text('Claimed', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isEligible && !busy ? onClaim : null,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(isEligible ? 'Claim reward' : 'Not yet eligible'),
      ),
    );
  }
}
