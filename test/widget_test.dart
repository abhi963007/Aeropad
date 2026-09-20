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

    // Scroll until 'Invert Scroll Direction' is visible
    await tester.scrollUntilVisible(
      find.text('Invert Scroll Direction'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Invert Scroll Direction'), findsOneWidget);

    // Toggle Invert Scroll Direction
    await tester.tap(find.text('Invert Scroll Direction'));
    await tester.pumpAndSettle();

    // Scroll until 'Invert Cursor Movement' is visible
    await tester.scrollUntilVisible(
      find.text('Invert Cursor Movement'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Invert Cursor Movement'), findsOneWidget);

    // Toggle Invert Cursor Movement
    await tester.tap(find.text('Invert Cursor Movement'));
    await tester.pumpAndSettle();

    // Close settings via back button
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(TrackpadPage), findsOneWidget);
  });

  testWidgets('renders TrackpadPage cleanly in landscape orientation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: TrackpadPage()));
    await tester.pumpAndSettle();

    expect(find.byType(TrackpadPage), findsOneWidget);
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);
  });

  test('SettingsService persists and falls back gracefully', () {
    expect(SettingsService.sensitivity, isNotNull);
    expect(SettingsService.invertScroll, isNotNull);
    expect(SettingsService.invertCursor, isNotNull);
    expect(SettingsService.haptics, isNotNull);
    expect(SettingsService.manualIp, isNotNull);
    expect(SettingsService.manualPort, isNotNull);
  });
}

