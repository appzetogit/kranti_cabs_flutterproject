import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutterdriver/features/auth/application/signup_providers.dart';

/// Signup progress has to survive the app being killed - Vivo phones kill it
/// while the camera is open on the documents step, and drivers were sent back
/// to the phone-number screen.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SignupData sample() => SignupData()
    ..registrationId = 'reg_123'
    ..phone = '9876543210'
    ..fullName = 'Ravi Kumar'
    ..email = 'ravi@example.com'
    ..gender = 'male'
    ..locationId = 'loc_blr'
    ..serviceCategories = ['taxi']
    ..vehicleTypeIds = ['auto_type']
    ..rcNumber = 'KA01AB1234'
    ..make = 'Bajaj'
    ..model = 'RE'
    ..year = '2021'
    ..number = 'KA01AB1234'
    ..color = 'Green'
    ..fuelType = 'CNG'
    ..resumeRoute = '/documents-upload';

  test('a saved signup comes back exactly as it was', () async {
    final data = sample()..documentPaths['driving_license'] = '/tmp/dl.jpg';
    await SignupProgressStore.save(data);

    final loaded = await SignupProgressStore.load();
    expect(loaded, isNotNull);
    expect(loaded!.toJson(), data.toJson());
    expect(loaded.resumeRoute, '/documents-upload');
    expect(loaded.documentPaths['driving_license'], '/tmp/dl.jpg');
  });

  test('nothing to resume before OTP is verified', () async {
    await SignupProgressStore.save(sample()..resumeRoute = '');
    expect(await SignupProgressStore.load(), isNull);
  });

  test('progress older than a day is dropped', () async {
    await SignupProgressStore.save(sample());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'driver_signup_progress_saved_at',
      DateTime.now().subtract(const Duration(hours: 25)).millisecondsSinceEpoch,
    );
    expect(await SignupProgressStore.load(), isNull);
  });

  test('cleared once registration completes', () async {
    await SignupProgressStore.save(sample());
    await SignupProgressStore.clear();
    expect(await SignupProgressStore.load(), isNull);
  });

  test('a corrupt save is ignored, not a crash', () async {
    SharedPreferences.setMockInitialValues({
      'driver_signup_progress_v1': '{not json',
      'driver_signup_progress_saved_at': DateTime.now().millisecondsSinceEpoch,
    });
    expect(await SignupProgressStore.load(), isNull);
  });
}
