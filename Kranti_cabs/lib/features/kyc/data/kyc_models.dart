class KycDocumentOption {
  final String type, label, flow, hint;
  final bool needsDob;
  bool get isOtp => flow == 'otp';

  KycDocumentOption.fromJson(Map<String, dynamic> j)
      : type = '${j['type']}',
        label = '${j['label'] ?? j['type']}',
        flow = '${j['flow'] ?? 'instant'}',
        hint = '${j['hint'] ?? ''}',
        needsDob = j['needsDob'] == true;
}

class KycConfig {
  final bool enabled, mockMode;
  final String requiredFor;
  final int otpExpiryMinutes;
  final List<KycDocumentOption> documents;

  KycConfig.fromJson(Map<String, dynamic> j)
      : enabled = j['enabled'] == true,
        mockMode = j['mockMode'] == true,
        requiredFor = '${j['requiredFor'] ?? 'optional'}',
        otpExpiryMinutes = (j['otpExpiryMinutes'] as num?)?.toInt() ?? 10,
        documents = ((j['documents'] ?? []) as List)
            .map((d) => KycDocumentOption.fromJson(Map<String, dynamic>.from(d as Map)))
            .toList();
}

class KycStatus {
  final String status, documentType, documentLabel, maskedNumber, verifiedName, failureReason;
  final KycConfig? config;

  bool get isVerified => status == 'verified';
  bool get underReview => status == 'needs_review';

  KycStatus.fromJson(Map<String, dynamic> j)
      : status = '${j['status'] ?? 'not_started'}',
        documentType = '${j['documentType'] ?? ''}',
        documentLabel = '${j['documentLabel'] ?? ''}',
        maskedNumber = '${j['maskedNumber'] ?? ''}',
        verifiedName = '${j['verifiedName'] ?? ''}',
        failureReason = '${j['failureReason'] ?? ''}',
        config = j['config'] is Map
            ? KycConfig.fromJson(Map<String, dynamic>.from(j['config'] as Map))
            : null;
}
