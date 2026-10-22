import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:taxiuser/features/ride/data/models/ride_model.dart';
import 'package:taxiuser/features/ride/presentation/ride_upi_pay_sheet.dart';

/// The "Pay your fare" screen: one-tap online payment, and paying the driver
/// directly on their own UPI QR or UPI ID.
void main() {
  RideModel ride({Map<String, dynamic>? driverPayment}) => RideModel.fromJson({
        'rideId': 'ride_1',
        'status': 'started',
        'liveStatus': 'started',
        'fare': 99,
        'paymentMethod': 'cash',
        'pickupLocation': {'type': 'Point', 'coordinates': [77.578, 12.977]},
        'dropLocation': {'type': 'Point', 'coordinates': [77.597, 13.035]},
        if (driverPayment != null) 'driverPayment': driverPayment,
      });

  Future<void> open(WidgetTester tester, RideModel r) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => RideUpiPaySheet.show(context, r), child: const Text('open')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a driver with a UPI ID: online, their QR, UPI ID, how-to and cash', (tester) async {
    await open(tester, ride(driverPayment: {'upiId': '7019805601@ybl', 'payeeName': 'Harsha Naik', 'qrCodeImage': ''}));

    expect(find.text('Pay ₹99 online'), findsOneWidget);
    expect(find.text('or pay the driver directly'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Harsha Naik · 7019805601@ybl'), findsOneWidget);
    expect(find.text('Save QR'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('7019805601@ybl'), findsOneWidget);
    expect(find.text('₹99'), findsWidgets);
    expect(find.text('How to pay your driver'), findsOneWidget);
    expect(find.text('I paid cash'), findsOneWidget);
  });

  test('the QR carries the driver UPI ID and no amount', () {
    const payment = RideDriverPayment(upiId: '7019805601@ybl', qrCodeImage: '', payeeName: 'Harsha Naik');
    final uri = Uri.parse(RideUpiPaySheet.driverUpiPayload(payment));
    expect(uri.scheme, 'upi');
    expect(uri.queryParameters['pa'], '7019805601@ybl');
    expect(uri.queryParameters['pn'], 'Harsha Naik');
    expect(uri.queryParameters.containsKey('am'), isFalse);
  });

  testWidgets('without a driver UPI only online and cash are offered', (tester) async {
    await open(tester, ride());
    expect(find.text('Pay ₹99 online'), findsOneWidget);
    expect(find.text('or pay the driver directly'), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('I paid cash'), findsOneWidget);
  });

  testWidgets('"I paid cash" closes the sheet', (tester) async {
    await open(tester, ride());
    await tester.tap(find.text('I paid cash'));
    await tester.pumpAndSettle();
    expect(find.text('Pay your fare'), findsNothing);
  });
}
