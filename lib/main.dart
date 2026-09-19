import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AeroPadApp());

enum HidConnection { disconnected, discoverable, connected }

class BondedDevice {
  const BondedDevice({required this.name, required this.address});
  final String name;
  final String address;
}

class HidBridge {
  static const _methods = MethodChannel('com.aeropad/hid');
  static const _events = EventChannel('com.aeropad/hid_state');

  Stream<HidStatus> get states => _events.receiveBroadcastStream().map((value) {
    final data = Map<Object?, Object?>.from(value as Map);
    switch (data['state']) {
      case 'connected':
        return HidStatus(
          HidConnection.connected,
          data['name'] as String? ?? 'Bluetooth host',
        );
      case 'discoverable':
        return const HidStatus(HidConnection.discoverable, '');
      default:
        return const HidStatus(HidConnection.disconnected, '');
    }
  });

  Future<void> connect() => _methods.invokeMethod('connect');
  Future<void> makeDiscoverable() => _methods.invokeMethod('makeDiscoverable');
  Future<void> disconnect() => _methods.invokeMethod('disconnect');
  Future<List<BondedDevice>> bondedDevices() async {
    final result =
        await _methods.invokeListMethod<Object?>('getBondedDevices') ??
        const [];
    return result.map((item) {
      final data = Map<Object?, Object?>.from(item as Map);
      return BondedDevice(
        name: data['name'] as String? ?? 'Unknown device',
        address: data['address'] as String? ?? '',
      );
    }).toList();
  }

  Future<void> connectToDevice(String address) =>
      _methods.invokeMethod('connectToDevice', {'address': address});

  Future<void> send({int buttons = 0, int dx = 0, int dy = 0, int wheel = 0}) =>
      _methods.invokeMethod('sendReport', {
        'buttons': buttons,
        'dx': dx,
        'dy': dy,
        'wheel': wheel,
      });
}

class HidStatus {
  const HidStatus(this.connection, this.deviceName);
  final HidConnection connection;
  final String deviceName;
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
  StreamSubscription<HidStatus>? _subscription;
  HidConnection _connection = HidConnection.disconnected;
  String _deviceName = '';
  double _sensitivity = 1;
  bool _invertScroll = false;
  bool _haptics = true;
  Offset? _last;
  bool _moved = false;
  int _fingerCount = 0;

  @override
  void initState() {
    super.initState();
    _subscription = _hid.states.listen(
      (status) => setState(() {
        _connection = status.connection;
        _deviceName = status.deviceName;
      }),
    );
    _hid.connect();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String get _status => switch (_connection) {
    HidConnection.connected =>
      'Connected: ${_deviceName.isEmpty ? 'Bluetooth host' : _deviceName}',
    HidConnection.discoverable => 'Discoverable / Pairing Mode...',
    HidConnection.disconnected => 'Disconnected',
  };

  int _accelerate(double value) {
    final magnitude = value.abs();
    return (((magnitude + magnitude * magnitude * .018) * value.sign) *
            _sensitivity)
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
      final direction = _invertScroll ? 1 : -1;
      _hid.send(wheel: (direction * delta.dy / 5).round().clamp(-127, 127));
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
    if (_haptics) HapticFeedback.selectionClick();
  }

  Future<void> _openSettings() async {
    final settings = await Navigator.of(context).push<SettingsResult>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          hid: _hid,
          sensitivity: _sensitivity,
          invertScroll: _invertScroll,
          haptics: _haptics,
          connected: _connection == HidConnection.connected,
        ),
      ),
    );
    if (!mounted || settings == null) return;
    setState(() {
      _sensitivity = settings.sensitivity;
      _invertScroll = settings.invertScroll;
      _haptics = settings.haptics;
    });
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
                GestureDetector(
                  onTap: _openSettings,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _connection == HidConnection.connected
                              ? const Color(0xff78e08f)
                              : _connection == HidConnection.discoverable
                              ? const Color(0xffffc857)
                              : const Color(0xff8d939b),
                          shape: BoxShape.circle,
                          boxShadow: _connection == HidConnection.connected
                              ? const [
                                  BoxShadow(
                                    color: Color(0x9978e08f),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
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
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _openSettings,
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

class SettingsResult {
  const SettingsResult({
    required this.sensitivity,
    required this.invertScroll,
    required this.haptics,
  });

  final double sensitivity;
  final bool invertScroll;
  final bool haptics;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.hid,
    required this.sensitivity,
    required this.invertScroll,
    required this.haptics,
    required this.connected,
    super.key,
  });

  final HidBridge hid;
  final double sensitivity;
  final bool invertScroll;
  final bool haptics;
  final bool connected;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _sensitivity = widget.sensitivity;
  late bool _invertScroll = widget.invertScroll;
  late bool _haptics = widget.haptics;
  List<BondedDevice> _devices = const [];
  bool _loadingDevices = true;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final devices = await widget.hid.bondedDevices();
      if (mounted) {
        setState(() {
          _devices = devices;
          _loadingDevices = false;
        });
      }
    } on PlatformException {
      if (mounted) setState(() => _loadingDevices = false);
    }
  }

  void _close() {
    Navigator.of(context).pop(
      SettingsResult(
        sensitivity: _sensitivity,
        invertScroll: _invertScroll,
        haptics: _haptics,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: const Color(0xff08090b),
      title: const Text(
        'Settings',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      leading: IconButton(
        onPressed: _close,
        icon: const Icon(Icons.arrow_back),
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        const _SectionTitle('Device Pairing'),
        _SettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Make your phone visible to nearby Bluetooth devices for five minutes.',
                style: TextStyle(color: Color(0xff9ca2aa), height: 1.4),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: widget.hid.makeDiscoverable,
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Make Phone Discoverable (5 Mins)'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff78e08f),
                  foregroundColor: const Color(0xff09100b),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const _SectionTitle('Paired Devices'),
            const Spacer(),
            IconButton(
              onPressed: _loadDevices,
              icon: const Icon(Icons.refresh, color: Color(0xff9ca2aa)),
            ),
          ],
        ),
        _SettingsCard(
          child: _loadingDevices
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _devices.isEmpty
              ? const Text(
                  'No paired Bluetooth computers found.',
                  style: TextStyle(color: Color(0xff9ca2aa)),
                )
              : Column(
                  children: _devices
                      .map(
                        (device) => _DeviceRow(
                          device: device,
                          hid: widget.hid,
                          connected: widget.connected,
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle('Pointer'),
        _SettingsCard(
          child: Column(
            children: [
              Row(
                children: [
                  const Text('Pointer Sensitivity'),
                  const Spacer(),
                  Text(
                    '${_sensitivity.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: Color(0xff78e08f),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _sensitivity,
                min: .5,
                max: 3,
                divisions: 10,
                label: '${_sensitivity.toStringAsFixed(1)}x',
                onChanged: (value) => setState(() => _sensitivity = value),
              ),
              const Divider(color: Color(0xff303238)),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Invert Scroll'),
                subtitle: const Text(
                  'Reverse two-finger scroll direction',
                  style: TextStyle(color: Color(0xff858b93)),
                ),
                value: _invertScroll,
                onChanged: (value) => setState(() => _invertScroll = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Haptic Vibration'),
                subtitle: const Text(
                  'Vibrate on mouse clicks',
                  style: TextStyle(color: Color(0xff858b93)),
                ),
                value: _haptics,
                onChanged: (value) => setState(() => _haptics = value),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _close,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xff78e08f),
            side: const BorderSide(color: Color(0xff303238)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Save Settings'),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Color(0xff78e08f),
      fontSize: 12,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.3,
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xff121316),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xff202226)),
    ),
    child: child,
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.hid,
    required this.connected,
  });
  final BondedDevice device;
  final HidBridge hid;
  final bool connected;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const CircleAvatar(
      backgroundColor: Color(0xff202d24),
      child: Icon(Icons.computer, color: Color(0xff78e08f)),
    ),
    title: Text(device.name),
    subtitle: Text(
      device.address,
      style: const TextStyle(color: Color(0xff747980), fontSize: 11),
    ),
    trailing: TextButton(
      onPressed: connected
          ? hid.disconnect
          : () => hid.connectToDevice(device.address),
      child: Text(connected ? 'Disconnect' : 'Connect'),
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
