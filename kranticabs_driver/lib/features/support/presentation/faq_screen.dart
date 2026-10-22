import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/custom_app_bar.dart';

class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

const _faqs = [
  _Faq(
    'How do I go online to receive ride requests?',
    'On the home screen, tap the "Go Online" button. You may be asked to take a quick selfie for verification before you start receiving requests.',
  ),
  _Faq(
    'How and when do I get paid?',
    'Your trip earnings are added to your in-app wallet after each completed ride. You can withdraw your wallet balance to your linked bank account anytime from the Earnings screen.',
  ),
  _Faq(
    'What do I do if a passenger cancels the ride?',
    'If a passenger cancels after you have accepted the trip, you may be eligible for a cancellation fee depending on how far along the pickup was. Check the Earnings screen for details.',
  ),
  _Faq(
    'How do I update my vehicle or documents?',
    'Go to Profile > Vehicle Details or Profile > Documents to update your vehicle information or re-upload documents such as your license, RC, or insurance.',
  ),
  _Faq(
    'What should I do in an emergency during a trip?',
    'Use the SOS button available on the active trip screen to alert your emergency contacts and support immediately.',
  ),
  _Faq(
    'How do incentives and bonuses work?',
    'Incentives are shown on the Incentives screen and are credited automatically to your wallet once you meet the target criteria for that period.',
  ),
  _Faq(
    'Can I change my registered phone number?',
    'Please raise a support ticket from the Help Center with your request, and our team will assist you in updating your registered number.',
  ),
];

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'FAQ'),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _faqs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final faq = _faqs[index];
          return Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.lightBorder),
              ),
              child: ExpansionTile(
                title: Text(faq.question, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    faq.answer,
                    style: const TextStyle(color: AppColors.lightTextSecondary, fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
