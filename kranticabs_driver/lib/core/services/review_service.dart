import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

class ReviewService {
  ReviewService._();

  /// Prompts the user/driver for an In-App Store Review if their rating is 4 or 5 stars,
  /// and the device/platform supports in-app review API.
  static Future<void> requestReviewIfEligible({required int rating}) async {
    if (rating < 4) {
      debugPrint('In-App Review: Rating is $rating (< 4). Skipping review request.');
      return;
    }

    try {
      final InAppReview inAppReview = InAppReview.instance;
      final bool isAvailable = await inAppReview.isAvailable();

      if (isAvailable) {
        debugPrint('In-App Review: Prompting store review dialog...');
        await inAppReview.requestReview();
      } else {
        debugPrint('In-App Review: API not available on this device/store.');
      }
    } catch (e) {
      debugPrint('In-App Review Error: Failed to trigger review: $e');
    }
  }
}
