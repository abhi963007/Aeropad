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

  testWidgets('renders disconnected state before native HID events', (
    tester,
  ) async {
    await tester.pumpWidget(const AeroPadApp());
    expect(find.text('Disconnected'), findsOneWidget);
  });
}
