import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AeroPadApp());

enum HidConnection { disconnected, discoverable, connected }

class HidBridge {
  static const _methods = MethodChannel('com.aeropad/hid');
  static const _events = EventChannel('com.aeropad/hid_state');

  Stream<HidConnection> get states =>
      _events.receiveBroadcastStream().map((value) {
        switch (value) {
          case 'connected':
            return HidConnection.connected;
          case 'discoverable':
            return HidConnection.discoverable;
          default:
            return HidConnection.disconnected;
        }
      });

  Future<void> connect() => _methods.invokeMethod('connect');

  Future<void> send({int buttons = 0, int dx = 0, int dy = 0, int wheel = 0}) =>
      _methods.invokeMethod('sendReport', {
        'buttons': buttons,
        'dx': dx,
        'dy': dy,
        'wheel': wheel,
      });
}

class AeroPadApp extends StatelessWidget {
  const AeroPadApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AeroPad',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff08090b),
      colorScheme: const ColorScheme.dark(primary: Color(0xff78e08f)),
    ),
    home: const TrackpadPage(),
  );
}

class TrackpadPage extends StatefulWidget {
  const TrackpadPage({super.key});
  @override
  State<TrackpadPage> createState() => _TrackpadPageState();
}

class _TrackpadPageState extends State<TrackpadPage> {
  final _hid = HidBridge();
  final Map<int, Offset> _pointers = {};
  final List<Offset> _traces = [];
  StreamSubscription<HidConnection>? _subscription;
  HidConnection _connection = HidConnection.disconnected;
  Offset? _last;
  bool _moved = false;
  int _fingerCount = 0;

  @override
  void initState() {
    super.initState();
    _subscription = _hid.states.listen(
      (state) => setState(() => _connection = state),
    );
    _hid.connect();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String get _status => switch (_connection) {
    HidConnection.connected => 'Connected: Windows PC',
    HidConnection.discoverable => 'Pairing / Discoverable',
    HidConnection.disconnected => 'Disconnected',
  };

  int _accelerate(double value) {
    final magnitude = value.abs();
    return ((magnitude + magnitude * magnitude * .018) * value.sign)
        .round()
        .clamp(-127, 127);
  }

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    _fingerCount = _pointers.length;
    _last = event.position;
    _moved = false;
    setState(() => _traces.add(event.position));
  }

  void _move(PointerMoveEvent event) {
    final previous = _last;
    _last = event.position;
    if (previous == null) return;
    final delta = event.position - previous;
    if (delta.distance < .1) return;
    _moved = true;
    setState(() {
      _traces.add(event.position);
      if (_traces.length > 20) _traces.removeAt(0);
    });
    if (_pointers.length >= 2) {
      _hid.send(wheel: (-delta.dy / 5).round().clamp(-127, 127));
    } else {
      _hid.send(dx: _accelerate(delta.dx), dy: _accelerate(delta.dy));
    }
  }

  void _up(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;
    if (!_moved) _click(_fingerCount >= 2 ? 2 : 1);
    _last = null;
    _moved = false;
    _fingerCount = 0;
    setState(() => _traces.clear());
  }

  Future<void> _click(int button) async {
    await _hid.send(buttons: button);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await _hid.send();
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  'AeroPad',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _connection == HidConnection.connected
                        ? const Color(0xff78e08f)
                        : const Color(0xff8d939b),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  _status,
                  style: const TextStyle(
                    color: Color(0xffb0b6bd),
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  onPressed: _hid.connect,
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Color(0xffb0b6bd),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: (event) => _pointers.remove(event.pointer),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff121316),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: CustomPaint(
                    painter: _SurfacePainter(_traces),
                    child: const Center(
                      child: Text(
                        '1-finger move • Tap to click • 2-finger scroll',
                        style: TextStyle(
                          color: Color(0xff747980),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ClickBar(onLeft: () => _click(1), onRight: () => _click(2)),
          ],
        ),
      ),
    ),
  );
}

class _SurfacePainter extends CustomPainter {
  _SurfacePainter(this.traces);
  final List<Offset> traces;
  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0xff26282c);
    for (double x = 11; x < size.width; x += 22) {
      for (double y = 11; y < size.height; y += 22) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
    for (var i = 0; i < traces.length; i++) {
      final opacity = (i + 1) / traces.length;
      canvas.drawCircle(
        traces[i],
        22,
        Paint()
          ..color = const Color(0xff78e08f).withValues(alpha: opacity * .25),
      );
      canvas.drawCircle(
        traces[i],
        4,
        Paint()..color = const Color(0xff78e08f).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SurfacePainter oldDelegate) =>
      oldDelegate.traces != traces;
}

class _ClickBar extends StatelessWidget {
  const _ClickBar({required this.onLeft, required this.onRight});
  final VoidCallback onLeft;
  final VoidCallback onRight;
  @override
  Widget build(BuildContext context) => Container(
    height: 72,
    decoration: BoxDecoration(
      color: const Color(0xff121316),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Button(icon: '◐', label: 'Left Click', onTap: onLeft),
        ),
        Container(width: 1, height: 38, color: const Color(0xff303238)),
        Expanded(
          child: _Button(icon: '◑', label: 'Right Click', onTap: onRight),
        ),
      ],
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.label, required this.onTap});
  final String icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          icon,
          style: const TextStyle(color: Color(0xff78e08f), fontSize: 27),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(color: Color(0xffb0b6bd), fontSize: 13),
        ),
      ],
    ),
  );
}
