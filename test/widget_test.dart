import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aeropad/main.dart';

void main() {
  testWidgets('renders the AeroPad trackpad surface and settings', (
    tester,
  ) async {
    await tester.pumpWidget(const AeroPadApp());
    expect(
      find.text('1-finger move • Tap to click • 2-finger scroll'),
      findsOneWidget,
    );
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}

