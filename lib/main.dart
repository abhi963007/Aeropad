import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const AeroPadApp());

enum NetworkState { disconnected, searching, connected }

class DiscoveredPc {
  const DiscoveredPc({
    required this.name,
    required this.address,
    this.port = 8989,
  });
  final String name;
  final String address;
  final int port;
}

class NetworkStatus {
  const NetworkStatus(this.state, {this.name = '', this.address = ''});
  final NetworkState state;
  final String name;
  final String address;
}

class NetworkMouseClient {
  static const commandPort = 8989;
  static const discoveryPort = 8988;
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _discoveryTimer;
  final _status = StreamController<NetworkStatus>.broadcast();
  final _pcs = StreamController<List<DiscoveredPc>>.broadcast();
  DiscoveredPc? _connected;

  Stream<NetworkStatus> get statuses => _status.stream;
  Stream<List<DiscoveredPc>> get discoveries => _pcs.stream;

  Future<void> start() async {
    _socket ??= await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;
    _subscription ??= _socket!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = _socket!.receive();
      if (datagram == null) return;
      _handleDiscovery(datagram.data, datagram.address.address);
    });
    _status.add(const NetworkStatus(NetworkState.searching));
    await discover();
    _discoveryTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => discover(),
    );
  }

  Future<void> discover() async {
    await startIfNeeded();
    final payload = utf8.encode(jsonEncode({'type': 'AEROPAD_DISCOVERY'}));
    final targets = <String>{
      '255.255.255.255',
      '192.168.137.1',
      '192.168.137.255',
      '192.168.43.1',
      '192.168.43.255',
      '192.168.0.255',
      '192.168.0.3',
      '192.168.1.255',
      '192.168.29.255',
      '192.168.31.255',
      '127.0.0.1',
    };

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.')) continue;
          final parts = ip.split('.');
          if (parts.length == 4) {
            final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            targets.add('$subnet.255');
            targets.add('$subnet.1');
            for (var i = 2; i <= 25; i++) {
              targets.add('$subnet.$i');
            }
          }
        }
      }
    } catch (_) {}

    for (final address in targets) {
      try {
        _socket!.send(payload, InternetAddress(address), discoveryPort);
      } on SocketException {
        // Continue probing other targets
      }
    }
    if (_connected == null) {
      _status.add(const NetworkStatus(NetworkState.searching));
    }
  }

  Future<void> startIfNeeded() async {
    if (_socket == null) await start();
  }

  void _handleDiscovery(List<int> bytes, String sourceAddress) {
    try {
      final packet = jsonDecode(utf8.decode(bytes));
      if (packet is! Map || packet['type'] != 'AEROPAD_DISCOVERY_RESPONSE') {
        return;
      }
      final pc = DiscoveredPc(
        name: '${packet['name'] ?? sourceAddress}',
        address: sourceAddress,
        port: (packet['port'] as num?)?.toInt() ?? commandPort,
      );
      if (_connected?.address != sourceAddress) {
        _pcs.add([pc]);
        connect(pc);
      }
    } catch (_) {
      // Ignore unrelated broadcast traffic on the discovery port.
    }
  }

  Future<void> connect(DiscoveredPc pc) async {
    await startIfNeeded();
    _connected = pc;
    _status.add(
      NetworkStatus(NetworkState.connected, name: pc.name, address: pc.address),
    );
  }

  Future<void> connectManual(String address, int port) async {
    final pc = DiscoveredPc(name: address, address: address, port: port);
    await connect(pc);
    send({'type': 'move', 'dx': 0, 'dy': 0});
  }

  void send(Map<String, Object> packet) {
    final target = _connected;
    final socket = _socket;
    if (target == null || socket == null) return;
    socket.send(
      utf8.encode(jsonEncode(packet)),
      InternetAddress(target.address),
      target.port,
    );
  }

  void move(int dx, int dy) => send({'type': 'move', 'dx': dx, 'dy': dy});
  void scroll(int dy) => send({'type': 'scroll', 'dy': dy});
  void click(String button) => send({'type': 'click', 'btn': button});
  void buttonDown(String button) => send({'type': 'down', 'btn': button});
  void buttonUp(String button) => send({'type': 'up', 'btn': button});

  Future<void> disconnect() async {
    _connected = null;
    _status.add(const NetworkStatus(NetworkState.disconnected));
  }

  Future<void> dispose() async {
    _discoveryTimer?.cancel();
    await _subscription?.cancel();
    _socket?.close();
    await _status.close();
    await _pcs.close();
  }
}

class AeroPadApp extends StatelessWidget {
  const AeroPadApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AeroPad',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: const Color(0xff090a0c),
      colorScheme: const ColorScheme.dark(primary: Color(0xff38bdf8)),
    ),
    home: const SplashScreen(),
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();

    _timer = Timer(const Duration(milliseconds: 1800), _navigateToTrackpad);
  }

  void _navigateToTrackpad() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const TrackpadPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: const Color(0xff090a0c),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Image.asset(
                'assets/splash_screen.png',
                width: size.width * 0.70,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TrackpadPage extends StatefulWidget {
  const TrackpadPage({super.key});
  @override
  State<TrackpadPage> createState() => _TrackpadPageState();
}

class _TrackpadPageState extends State<TrackpadPage> {
  final _network = NetworkMouseClient();
  final Map<int, Offset> _pointers = {};
  StreamSubscription<NetworkStatus>? _statusSubscription;
  NetworkState _state = NetworkState.searching;
  String _address = '';
  double _sensitivity = 1;
  bool _invertScroll = false;
  bool _haptics = true;
  double _scrollAccumulator = 0.0;
  Offset? _last;
  Offset? _downPosition;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;
  bool _moved = false;
  bool _isPotentialDrag = false;
  bool _dragging = false;
  int _fingerCount = 0;

  @override
  void initState() {
    super.initState();
    _statusSubscription = _network.statuses.listen((status) {
      if (!mounted) return;
      setState(() {
        _state = status.state;
        _address = status.address;
      });
    });
    _network.start();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _network.dispose();
    super.dispose();
  }

  Color get _indicatorColor => switch (_state) {
    NetworkState.connected => const Color(0xff2ecc71),
    NetworkState.searching => const Color(0xffffc857),
    NetworkState.disconnected => const Color(0xffff5252),
  };

  int _accelerate(double value) {
    final magnitude = value.abs();
    return (((magnitude + magnitude * magnitude * .018) * value.sign) *
            _sensitivity)
        .round()
        .clamp(-32767, 32767);
  }

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    _fingerCount = _pointers.length;
    _last = event.position;
    _downPosition = event.position;
    _moved = false;

    if (_fingerCount >= 2) {
      _scrollAccumulator = 0.0;
    }

    if (_fingerCount == 1 &&
        _lastTapTime != null &&
        _lastTapPosition != null &&
        DateTime.now().difference(_lastTapTime!).inMilliseconds < 350 &&
        (event.position - _lastTapPosition!).distance < 50) {
      _isPotentialDrag = true;
      _dragging = false;
    } else {
      _isPotentialDrag = false;
      _dragging = false;
    }
  }

  void _move(PointerMoveEvent event) {
    final previous = _last;
    _last = event.position;
    if (previous == null) return;
    final delta = event.position - previous;
    if (delta.distance < .1) return;

    final totalDistance = _downPosition != null
        ? (event.position - _downPosition!).distance
        : delta.distance;

    if (totalDistance > 6.0) {
      _moved = true;
    }

    if (_pointers.length >= 2) {
      if (_dragging) {
        _network.buttonUp('left');
        _dragging = false;
      }
      _isPotentialDrag = false;
      final direction = _invertScroll ? 1.0 : -1.0;
      _scrollAccumulator += direction * delta.dy * _sensitivity * 0.35;
      if (_scrollAccumulator.abs() >= 1.0) {
        final steps = _scrollAccumulator.truncate();
        _network.scroll(steps);
        _scrollAccumulator -= steps;
      }
    } else {
      if (_isPotentialDrag && _moved && !_dragging) {
        _dragging = true;
        _network.buttonDown('left');
        if (_haptics) HapticFeedback.selectionClick();
      }
      _network.move(_accelerate(delta.dx), _accelerate(delta.dy));
    }
  }

  void _up(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;

    final totalDistance = _downPosition != null
        ? (event.position - _downPosition!).distance
        : 0.0;
    final didMove = _moved || totalDistance > 6.0;

    if (_dragging) {
      _network.buttonUp('left');
      if (_haptics) HapticFeedback.selectionClick();
      _dragging = false;
      _isPotentialDrag = false;
      _lastTapTime = null;
      _lastTapPosition = null;
    } else if (_isPotentialDrag && !didMove) {
      _network.click('left');
      if (_haptics) HapticFeedback.selectionClick();
      _isPotentialDrag = false;
      _lastTapTime = null;
      _lastTapPosition = null;
    } else if (!didMove) {
      final button = _fingerCount >= 2 ? 'right' : 'left';
      _network.click(button);
      if (_fingerCount == 1) {
        _lastTapTime = DateTime.now();
        _lastTapPosition = event.position;
      } else {
        _lastTapTime = null;
        _lastTapPosition = null;
      }
      if (_haptics) HapticFeedback.selectionClick();
    } else {
      _lastTapTime = null;
      _lastTapPosition = null;
    }

    _last = null;
    _downPosition = null;
    _moved = false;
    _dragging = false;
    _isPotentialDrag = false;
    _fingerCount = 0;
    _scrollAccumulator = 0.0;
  }

  void _cancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty && _dragging) {
      _network.buttonUp('left');
      _dragging = false;
    }
    _isPotentialDrag = false;
    _last = null;
    _downPosition = null;
    _fingerCount = 0;
    _scrollAccumulator = 0.0;
  }

  Future<void> _openSettings() async {
    final settings = await Navigator.of(context).push<SettingsResult>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          network: _network,
          sensitivity: _sensitivity,
          invertScroll: _invertScroll,
          haptics: _haptics,
          connected: _state == NetworkState.connected,
          connectedAddress: _address,
          onSettingsChanged: (updated) {
            setState(() {
              _sensitivity = updated.sensitivity;
              _invertScroll = updated.invertScroll;
              _haptics = updated.haptics;
            });
          },
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
    backgroundColor: const Color(0xff090a0c),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_state == NetworkState.disconnected) {
                      _network.discover();
                    } else {
                      _openSettings();
                    }
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xff121316),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xff202226),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: _indicatorColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _indicatorColor.withValues(alpha: 0.5),
                                blurRadius: 3,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: Color(0xff8a909a),
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Listener(
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _cancel,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff121316),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xff202226),
                      width: 1,
                    ),
                  ),
                  child: const SizedBox.expand(
                    child: CustomPaint(
                      painter: _DotGridPainter(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _ClickBar(
              onLeft: () {
                _network.click('left');
                if (_haptics) HapticFeedback.selectionClick();
              },
              onRight: () {
                _network.click('right');
                if (_haptics) HapticFeedback.selectionClick();
              },
            ),
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
    required this.network,
    required this.sensitivity,
    required this.invertScroll,
    required this.haptics,
    required this.connected,
    required this.connectedAddress,
    this.onSettingsChanged,
    super.key,
  });
  final NetworkMouseClient network;
  final double sensitivity;
  final bool invertScroll;
  final bool haptics;
  final bool connected;
  final String connectedAddress;
  final ValueChanged<SettingsResult>? onSettingsChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _sensitivity = widget.sensitivity;
  late bool _invertScroll = widget.invertScroll;
  late bool _haptics = widget.haptics;
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '8989');
  DiscoveredPc? _discovered;
  StreamSubscription<List<DiscoveredPc>>? _discoverySubscription;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _discoverySubscription = widget.network.discoveries.listen((pcs) {
      if (mounted && pcs.isNotEmpty) {
        setState(() {
          _discovered = pcs.first;
          _isScanning = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _discoverySubscription?.cancel();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _notifyChange() {
    final result = SettingsResult(
      sensitivity: _sensitivity,
      invertScroll: _invertScroll,
      haptics: _haptics,
    );
    widget.onSettingsChanged?.call(result);
  }

  void _close() {
    _notifyChange();
    Navigator.of(context).pop(
      SettingsResult(
        sensitivity: _sensitivity,
        invertScroll: _invertScroll,
        haptics: _haptics,
      ),
    );
  }

  Future<void> _manualConnect() async {
    final port = int.tryParse(_portController.text.trim()) ?? 8989;
    final ip = _ipController.text.trim();
    if (ip.isNotEmpty) {
      await widget.network.connectManual(ip, port);
    }
  }

  Future<void> _triggerScan() async {
    setState(() => _isScanning = true);
    await widget.network.discover();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    onPopInvokedWithResult: (didPop, result) {
      _notifyChange();
    },
    child: Scaffold(
      backgroundColor: const Color(0xff090a0c),
      appBar: AppBar(
        backgroundColor: const Color(0xff090a0c),
        elevation: 0,
        leading: IconButton(
          onPressed: _close,
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xffe0e4e8),
            size: 18,
          ),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xffe0e4e8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionTitle('Network'),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_discovered != null) ...[
                  Builder(
                    builder: (context) {
                      final isCurrentPcConnected = widget.connected &&
                          (widget.connectedAddress == _discovered!.address ||
                              widget.connectedAddress == _discovered!.name);
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xff0d0e12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrentPcConnected
                                ? const Color(0xff1b3323)
                                : const Color(0xff1e2229),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isCurrentPcConnected
                                    ? const Color(0xff12281a)
                                    : const Color(0xff181a20),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.laptop_chromebook_rounded,
                                color: isCurrentPcConnected
                                    ? const Color(0xff2ecc71)
                                    : const Color(0xffa8b0ba),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _discovered!.name,
                                    style: const TextStyle(
                                      color: Color(0xffe0e4e8),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_discovered!.address}:${_discovered!.port}',
                                    style: const TextStyle(
                                      color: Color(0xff6e7681),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrentPcConnected) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xff12281a),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xff2ecc71),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    const Text(
                                      'Connected',
                                      style: TextStyle(
                                        color: Color(0xff2ecc71),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: widget.network.disconnect,
                                tooltip: 'Disconnect',
                                icon: const Icon(
                                  Icons.link_off_rounded,
                                  color: Color(0xffef4444),
                                  size: 18,
                                ),
                              ),
                            ] else
                              OutlinedButton(
                                onPressed: () =>
                                    widget.network.connect(_discovered!),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xffe0e4e8),
                                  side: const BorderSide(
                                    color: Color(0xff282c35),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Connect',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: _isScanning
                            ? Icons.hourglass_top_rounded
                            : Icons.radar_rounded,
                        label: _isScanning ? 'Scanning...' : 'Auto-Discover',
                        onTap: _triggerScan,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.wifi_rounded,
                        label: 'Wi-Fi (192.168.0.3)',
                        onTap: () => widget.network.connectManual(
                          '192.168.0.3',
                          8989,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: Icons.router_outlined,
                  label: 'Hotspot Gateway (192.168.137.1)',
                  onTap: () => widget.network.connectManual(
                    '192.168.137.1',
                    8989,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Manual Connection'),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _ipController,
                        keyboardType: TextInputType.datetime,
                        style: const TextStyle(
                          color: Color(0xffe0e4e8),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '192.168.0.3',
                          hintStyle: const TextStyle(
                            color: Color(0xff4a505b),
                          ),
                          prefixIcon: const Icon(
                            Icons.lan_outlined,
                            size: 16,
                            color: Color(0xff6e7681),
                          ),
                          filled: true,
                          fillColor: const Color(0xff0b0c0f),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xff202226),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xff202226),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xff38bdf8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: Color(0xffe0e4e8),
                          fontSize: 13,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '8989',
                          hintStyle: const TextStyle(
                            color: Color(0xff4a505b),
                          ),
                          prefixIcon: const Icon(
                            Icons.tag_rounded,
                            size: 16,
                            color: Color(0xff6e7681),
                          ),
                          filled: true,
                          fillColor: const Color(0xff0b0c0f),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xff202226),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xff202226),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xff38bdf8),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _manualConnect,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text(
                      'Connect to IP',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xffe0e4e8),
                      backgroundColor: const Color(0xff16181f),
                      side: const BorderSide(color: Color(0xff252932)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Tuning'),
          const SizedBox(height: 8),
          _SettingsCard(
            child: Column(
              children: [
                Row(
                  children: [
                    const Text(
                      'Cursor Sensitivity',
                      style: TextStyle(
                        color: Color(0xffe0e4e8),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff181a20),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xff252932)),
                      ),
                      child: Text(
                        '${_sensitivity.toStringAsFixed(1)}x',
                        style: const TextStyle(
                          color: Color(0xffa8b0ba),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xff64748b),
                    inactiveTrackColor: const Color(0xff1c1f26),
                    thumbColor: const Color(0xffe2e8f0),
                    overlayColor: Colors.transparent,
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: _sensitivity,
                    min: .5,
                    max: 3,
                    divisions: 10,
                    onChanged: (value) {
                      setState(() => _sensitivity = value);
                      _notifyChange();
                    },
                  ),
                ),
                const Divider(color: Color(0xff1c1f24), height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Invert Scroll Direction',
                    style: TextStyle(
                      color: Color(0xffe0e4e8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  subtitle: const Text(
                    'Natural 2-finger scroll (push content)',
                    style: TextStyle(
                      color: Color(0xff6e7681),
                      fontSize: 11,
                    ),
                  ),
                  activeThumbColor: const Color(0xffe2e8f0),
                  activeTrackColor: const Color(0xff334155),
                  value: _invertScroll,
                  onChanged: (value) {
                    setState(() => _invertScroll = value);
                    _notifyChange();
                  },
                ),
                const Divider(color: Color(0xff1c1f24), height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Haptic Feedback',
                    style: TextStyle(
                      color: Color(0xffe0e4e8),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  subtitle: const Text(
                    'Tactile feedback on clicks & gestures',
                    style: TextStyle(
                      color: Color(0xff6e7681),
                      fontSize: 11,
                    ),
                  ),
                  activeThumbColor: const Color(0xffe2e8f0),
                  activeTrackColor: const Color(0xff334155),
                  value: _haptics,
                  onChanged: (value) {
                    setState(() => _haptics = value);
                    _notifyChange();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xff16181f),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff22252e)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 15, color: const Color(0xff94a3b8)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xffc5ccd4),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
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
      color: Color(0xff6e7681),
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3,
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xff121316),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xff202226), width: 1.0),
    ),
    child: child,
  );
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0xff22252a);
    for (double x = 16; x < size.width; x += 24) {
      for (double y = 16; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 1.0, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ClickBar extends StatelessWidget {
  const _ClickBar({required this.onLeft, required this.onRight});
  final VoidCallback onLeft;
  final VoidCallback onRight;

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    decoration: BoxDecoration(
      color: const Color(0xff121316),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xff202226), width: 1),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Button(
            isRight: false,
            label: 'Left Click',
            onTap: onLeft,
          ),
        ),
        Container(width: 1, height: 40, color: const Color(0xff23262b)),
        Expanded(
          child: _Button(
            isRight: true,
            label: 'Right Click',
            onTap: onRight,
          ),
        ),
      ],
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button({
    required this.isRight,
    required this.label,
    required this.onTap,
  });

  final bool isRight;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _MouseIcon(isRight: isRight),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xffe0e4e8),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    ),
  );
}

class _MouseIcon extends StatelessWidget {
  const _MouseIcon({required this.isRight});
  final bool isRight;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(18, 27),
    painter: _MouseIconPainter(isRight: isRight),
  );
}

class _MouseIconPainter extends CustomPainter {
  const _MouseIconPainter({required this.isRight});
  final bool isRight;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeColor = Color(0xffa8b0ba);
    const fillColor = Color(0xffe2e8f0);
    const cornerRadius = 7.0;
    final splitY = size.height * 0.42;
    final splitX = size.width * 0.5;

    final borderPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    // Fill active button
    if (!isRight) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(0, 0, splitX, splitY),
          topLeft: const Radius.circular(cornerRadius),
        ),
        fillPaint,
      );
    } else {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(splitX, 0, splitX, splitY),
          topRight: const Radius.circular(cornerRadius),
        ),
        fillPaint,
      );
    }

    // Outer capsule outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(cornerRadius),
      ),
      borderPaint,
    );

    // Horizontal divider
    canvas.drawLine(
      Offset(0, splitY),
      Offset(size.width, splitY),
      borderPaint,
    );

    // Vertical top divider between left & right buttons
    canvas.drawLine(
      Offset(splitX, 0),
      Offset(splitX, splitY),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MouseIconPainter oldDelegate) =>
      oldDelegate.isRight != isRight;
}
