import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aeropad/main.dart';

void main() {
  testWidgets('renders AeroPad splash screen and transitions to trackpad', (
    tester,
  ) async {
    await tester.pumpWidget(const AeroPadApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    // Fast-forward past the splash timer (1800ms) and fade transition (350ms)
    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pumpAndSettle();

    expect(
      find.text('1-finger move • Tap to click • 2-finger scroll'),
      findsNothing,
    );
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Open settings
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    // Scroll until 'Connect to IP' is visible
    await tester.scrollUntilVisible(
      find.text('Connect to IP'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Connect to IP'), findsOneWidget);

    // Tap Connect to IP button to open manual connection popup
    await tester.tap(find.text('Connect to IP'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Manual Connection'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    // Close popup
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
  });
}

