import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterdriver/core/theme/app_theme.dart';

void main() {
  testWidgets('App theme renders a basic scaffold', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: Text('KrantiCabs Rider'))),
      ),
    );

    expect(find.text('KrantiCabs Rider'), findsOneWidget);
  });
}
