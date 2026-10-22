import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../application/kyc_providers.dart';
import '../data/kyc_models.dart';

const _gold = Color(0xFFF5B400);

// Mirrors the server's format checks so a typo costs no verification attempt.
final _formats = {
  'aadhaar': RegExp(r'^[2-9][0-9]{11}$'),
  'pan': RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$'),
  'voter_id': RegExp(r'^[A-Z]{3}[0-9]{7}$'),
  'driving_license': RegExp(r'^[A-Z]{2}[0-9]{2}[0-9A-Z]{9,14}$'),
};

/// Pops `true` when the rider ends up verified and [returnToBooking] is set.
class VerifyIdentityScreen extends ConsumerStatefulWidget {
  final bool returnToBooking;
  const VerifyIdentityScreen({super.key, this.returnToBooking = false});

  @override
  ConsumerState<VerifyIdentityScreen> createState() => _VerifyIdentityScreenState();
}

class _VerifyIdentityScreenState extends ConsumerState<VerifyIdentityScreen> {
  final _number = TextEditingController();
  final _otp = TextEditingController();
  String? _type;
  DateTime? _dob;
  bool _busy = false;
  bool _otpSent = false;
  String? _error, _mockOtp, _maskedAadhaar;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _number.dispose();
    _otp.dispose();
    super.dispose();
  }

  String get _clean {
    final v = _number.text.replaceAll(' ', '');
    return _type == 'aadhaar' ? v : v.toUpperCase();
  }

  bool _ready(KycDocumentOption doc) {
    if (_busy) return false;
    if (_otpSent) return _otp.text.trim().length >= 4;
    return _clean.isNotEmpty && (!doc.needsDob || _dob != null);
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _secondsLeft <= 1) {
        t.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _resetOtpStep() {
    _timer?.cancel();
    setState(() {
      _otpSent = false;
      _otp.clear();
      _mockOtp = null;
      _secondsLeft = 0;
    });
  }

  Future<void> _submit(KycDocumentOption doc) async {
    final repo = ref.read(kycRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (doc.isOtp && !_otpSent) {
        if (!_formats['aadhaar']!.hasMatch(_clean)) {
          throw ApiException('Enter a valid 12-digit Aadhaar number');
        }
        final res = await repo.sendAadhaarOtp(_clean);
        _maskedAadhaar = '${res['maskedNumber'] ?? ''}';
        _mockOtp = res['mockOtp']?.toString();
        setState(() => _otpSent = true);
        _startTimer((res['expiresInSeconds'] as num?)?.toInt() ?? 600);
        return;
      }
      if (!doc.isOtp) {
        final fmt = _formats[doc.type];
        if (fmt != null && !fmt.hasMatch(_clean)) {
          throw ApiException(doc.hint.isNotEmpty ? 'Invalid ${doc.label}: ${doc.hint}' : 'Invalid ${doc.label} number');
        }
      }
      if (doc.isOtp) {
        await repo.verifyAadhaarOtp(_otp.text.trim());
      } else {
        await repo.verifyDocument(
          doc.type,
          _clean,
          dob: doc.needsDob ? _dob!.toIso8601String().substring(0, 10) : null,
        );
      }
      ref.invalidate(kycStatusProvider);
      _timer?.cancel();
      setState(() {});
    } on ApiException catch (e) {
      // Expired OTP: the request is dead, so start again from the number.
      if (e.code == 'KYC_OTP_EXPIRED') _resetOtpStep();
      // Already verified / under review: the status screen explains it.
      if (e.statusCode == 409) ref.invalidate(kycStatusProvider);
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(kycStatusProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF11191D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF11191D),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Verify Identity', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _gold)),
        error: (e, _) => _Message(
          icon: Icons.error_outline_rounded,
          text: e is ApiException ? e.message : 'Could not load verification status.',
          action: TextButton(onPressed: () => ref.invalidate(kycStatusProvider), child: const Text('Retry')),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(KycStatus s) {
    final cfg = s.config;
    if (s.isVerified) {
      return _Message(
        icon: Icons.verified_rounded,
        color: const Color(0xFF10B981),
        title: "You're verified",
        text: '${s.documentLabel} ${s.maskedNumber}${s.verifiedName.isEmpty ? '' : ' · ${s.verifiedName}'}',
        action: widget.returnToBooking
            ? ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.black),
                onPressed: () => context.pop(true),
                child: const Text('Continue booking'),
              )
            : null,
      );
    }
    if (s.underReview) {
      return const _Message(
        icon: Icons.schedule_rounded,
        title: 'Under review',
        text: "We've received your document. You can book once it's approved.",
      );
    }
    if (cfg == null || !cfg.enabled || cfg.documents.isEmpty) {
      return const _Message(icon: Icons.check_circle_outline, text: 'No verification needed');
    }

    final doc = cfg.documents.firstWhere((d) => d.type == _type, orElse: () => cfg.documents.first);
    _type ??= doc.type;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Verify your identity to book rides. Your full document number is never stored.',
            style: TextStyle(color: Color(0xFF94A3B8))),
        if ((s.status == 'failed' || s.status == 'rejected') && s.failureReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ErrorBox(s.failureReason),
        ],
        const SizedBox(height: 18),
        const Text('Choose a document', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final d in cfg.documents)
              ChoiceChip(
                label: Text('${d.label} · ${d.isOtp ? 'OTP verification' : 'Instant'}'),
                selected: d.type == doc.type,
                selectedColor: _gold,
                labelStyle: TextStyle(color: d.type == doc.type ? Colors.black : Colors.white),
                backgroundColor: const Color(0xFF222222),
                // Locked while an OTP is pending so the number can't change under it.
                onSelected: _otpSent
                    ? null
                    : (_) => setState(() {
                          _type = d.type;
                          _number.clear();
                          _error = null;
                        }),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (!_otpSent) ...[
          TextField(
            controller: _number,
            enabled: !_busy,
            style: const TextStyle(color: Colors.white),
            keyboardType: doc.type == 'aadhaar' ? TextInputType.number : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: doc.type == 'aadhaar'
                ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12), _AadhaarSpacing()]
                : [FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))],
            onChanged: (_) => setState(() {}),
            decoration: _deco('${doc.label} number', doc.hint),
          ),
          if (doc.needsDob) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Color(0xFF2E2E2E))),
              icon: const Icon(Icons.cake_outlined),
              label: Text(_dob == null ? 'Date of birth' : _dob!.toIso8601String().substring(0, 10)),
              onPressed: _busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _dob ?? DateTime(now.year - 25),
                        firstDate: DateTime(1920),
                        lastDate: now,
                      );
                      if (d != null) setState(() => _dob = d);
                    },
            ),
          ],
        ] else ...[
          Text('Sent to the mobile linked with Aadhaar $_maskedAadhaar',
              style: const TextStyle(color: Color(0xFF94A3B8))),
          if (_mockOtp != null) Text('Test OTP: $_mockOtp', style: const TextStyle(color: _gold)),
          const SizedBox(height: 10),
          TextField(
            controller: _otp,
            enabled: !_busy,
            style: const TextStyle(color: Colors.white, letterSpacing: 4),
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
            onChanged: (_) => setState(() {}),
            decoration: _deco('Enter OTP', _secondsLeft > 0 ? 'Expires in ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}' : 'OTP expired'),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _resetOtpStep,
              child: Text(_secondsLeft > 0 ? 'Change number' : 'Resend OTP'),
            ),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 12), _ErrorBox(_error!)],
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _ready(doc) ? () => _submit(doc) : null,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black))
                : Text(doc.isOtp ? (_otpSent ? 'Verify OTP' : 'Send OTP') : 'Verify',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
        ),
      ],
    );
  }

  InputDecoration _deco(String label, String helper) => InputDecoration(
        labelText: label,
        helperText: helper,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        helperStyle: const TextStyle(color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: const Color(0xFF222222),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      );
}

/// Formats Aadhaar as XXXX XXXX XXXX while typing.
class _AadhaarSpacing extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) {
    final d = v.text.replaceAll(' ', '');
    final out = [for (var i = 0; i < d.length; i += 4) d.substring(i, i + 4 > d.length ? d.length : i + 4)].join(' ');
    return TextEditingValue(text: out, selection: TextSelection.collapsed(offset: out.length));
  }
}

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: Text(text, style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w600)),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? title;
  final String text;
  final Widget? action;
  const _Message({required this.icon, required this.text, this.title, this.action, this.color = _gold});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 64, color: color),
            if (title != null) ...[
              const SizedBox(height: 12),
              Text(title!, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF94A3B8))),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}
