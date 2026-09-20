import 'package:flutter_test/flutter_test.dart';
import 'package:aeropad/main.dart';

void main() {
  testWidgets('renders the AeroPad trackpad surface', (tester) async {
    await tester.pumpWidget(const AeroPadApp());
    expect(find.text('AeroPad'), findsOneWidget);
    expect(
      find.text('1-finger move • Tap to click • 2-finger scroll'),
      findsOneWidget,
    );
    expect(find.text('Left Click'), findsOneWidget);
    expect(find.text('Right Click'), findsOneWidget);
  });

  testWidgets('renders searching state before network discovery completes', (
    tester,
  ) async {
    await tester.pumpWidget(const AeroPadApp());
    expect(find.text('Searching for PC on Wi-Fi...'), findsOneWidget);
  });
}
