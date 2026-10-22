import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/kyc_models.dart';
import '../data/kyc_repository.dart';

final kycRepositoryProvider = Provider<KycRepository>((ref) => KycRepository(ref.watch(apiClientProvider)));

/// Current KYC status + admin config. Invalidate after a verification attempt.
final kycStatusProvider = FutureProvider.autoDispose<KycStatus>(
  (ref) => ref.watch(kycRepositoryProvider).status(),
);
