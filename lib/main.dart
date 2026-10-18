import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MotoDashboardApp());
}

class MotoDashboardApp extends StatelessWidget {
  const MotoDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moto Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<Color> _themes = [
    const Color(0xFF00FF66), // Racing Green
    const Color(0xFFFF6600), // KTM Orange
    const Color(0xFF00E5FF), // Neon Blue
    Colors.white,           // High-Contrast White
  ];
  int _currentThemeIndex = 0;
  Color get _accentColor => _themes[_currentThemeIndex];

  double _rawRoll = 0.0;
  double _rawPitch = 0.0;
  double _calibratedRoll = 0.0;
  double _calibratedPitch = 0.0;
  double _zeroRollOffset = 0.0;
  double _zeroPitchOffset = 0.0;

  double _maxRollLeft = 0.0;
  double _maxRollRight = 0.0;

  double _speedKmh = 0.0;
  double _maxSpeedKmh = 0.0;
  double _tripDistanceKm = 0.0;
  double _avgConsumptionL100 = 5.5;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;

  @override
  void initState() {
    super.initState();
    _initSensors();
    _initGps();
  }

  void _initSensors() {
    _accelSub = accelerometerEvents.listen((AccelerometerEvent event) {
      double roll = math.atan2(event.x, math.sqrt(event.y * event.y + event.z * event.z)) * (180 / math.pi);
      double pitch = math.atan2(-event.y, event.z) * (180 / math.pi);

      setState(() {
        _rawRoll = roll;
        _rawPitch = pitch;
        _calibratedRoll = _rawRoll - _zeroRollOffset;
        _calibratedPitch = _rawPitch - _zeroPitchOffset;

        if (_calibratedRoll < 0 && _calibratedRoll.abs() > _maxRollLeft) {
          _maxRollLeft = _calibratedRoll.abs();
        } else if (_calibratedRoll > 0 && _calibratedRoll > _maxRollRight) {
          _maxRollRight = _calibratedRoll;
        }
      });
    });
  }

  Future<void> _initGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      double speed = position.speed * 3.6;
      if (speed < 0) speed = 0;

      if (_lastPosition != null) {
        double distMeters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        _tripDistanceKm += distMeters / 1000.0;
      }
      _lastPosition = position;

      setState(() {
        _speedKmh = speed;
        if (_speedKmh > _maxSpeedKmh) {
          _maxSpeedKmh = _speedKmh;
        }
      });
    });
  }

  void _calibrateZero() {
    setState(() {
      _zeroRollOffset = _rawRoll;
      _zeroPitchOffset = _rawPitch;
      _maxRollLeft = 0.0;
      _maxRollRight = 0.0;
    });
  }

  void _resetMax() {
    setState(() {
      _maxRollLeft = 0.0;
      _maxRollRight = 0.0;
      _maxSpeedKmh = 0.0;
      _tripDistanceKm = 0.0;
    });
  }

  void _cycleTheme() {
    setState(() {
      _currentThemeIndex = (_currentThemeIndex + 1) % _themes.length;
    });
  }

  Future<void> _launchAssistant() async {
    final Uri url = Uri.parse('https://gemini.google.com');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _accelSub?.cancel();
    _positionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final totalFuelConsumed = (_tripDistanceKm * _avgConsumptionL100) / 100.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(
              child: isLandscape ? _buildLandscapeLayout(totalFuelConsumed) : _buildPortraitLayout(totalFuelConsumed),
            ),
            _buildGloveBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[900],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.gps_fixed, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'GPS: ${_speedKmh > 0 ? "OK" : "BUSCANDO"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          Row(
            children: [
              Icon(Icons.bluetooth, color: _accentColor, size: 20),
              const SizedBox(width: 12),
              Text(
                DateTime.now().toString().substring(11, 16),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout(double fuelConsumed) {
    return Row(
      children: [
        Expanded(child: _buildGaugeCard('ROLL (INCLINACIÓN)', _calibratedRoll, 'L: ${_maxRollLeft.toStringAsFixed(1)}° | R: ${_maxRollRight.toStringAsFixed(1)}°')),
        Expanded(child: _buildCenterSpeedometer(fuelConsumed)),
        Expanded(child: _buildGaugeCard('PITCH (ACEL/FRENO)', _calibratedPitch, 'PITCH: ${_calibratedPitch.toStringAsFixed(1)}°')),
      ],
    );
  }

  Widget _buildPortraitLayout(double fuelConsumed) {
    return Column(
      children: [
        Expanded(flex: 2, child: _buildCenterSpeedometer(fuelConsumed)),
        Expanded(
          flex: 2,
          child: Row(
            children: [
              Expanded(child: _buildGaugeCard('ROLL', _calibratedRoll, 'L: ${_maxRollLeft.toStringAsFixed(1)}° | R: ${_maxRollRight.toStringAsFixed(1)}°')),
              Expanded(child: _buildGaugeCard('PITCH', _calibratedPitch, 'PITCH: ${_calibratedPitch.toStringAsFixed(1)}°')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterSpeedometer(double fuelConsumed) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _speedKmh.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 88,
            fontWeight: FontWeight.bold,
            color: _accentColor,
            height: 1.0,
          ),
        ),
        const Text('KM/H', style: TextStyle(fontSize: 20, color: Colors.grey, letterSpacing: 2)),
        const SizedBox(height: 12),
        Text('MÁX: ${_maxSpeedKmh.toStringAsFixed(0)} KM/H', style: const TextStyle(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 6),
        Text('TRIP: ${_tripDistanceKm.toStringAsFixed(1)} KM | EST. FUEL: ${fuelConsumed.toStringAsFixed(2)} L',
            style: TextStyle(fontSize: 12, color: _accentColor)),
      ],
    );
  }

  Widget _buildGaugeCard(String title, double angleValue, String subtitle) {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withOpacity(0.4), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CircularProgressIndicator(
                  value: (angleValue.abs() / 60.0).clamp(0.0, 1.0),
                  strokeWidth: 10,
                  color: _accentColor,
                  backgroundColor: Colors.grey[800],
                ),
              ),
              Text(
                '${angleValue.toStringAsFixed(1)}°',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(subtitle, style: TextStyle(fontSize: 11, color: _accentColor)),
        ],
      ),
    );
  }

  Widget _buildGloveBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      color: Colors.grey[950],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildGloveButton(Icons.screen_rotation, 'CERO', _calibrateZero),
          _buildGloveButton(Icons.refresh, 'RESET', _resetMax),
          _buildGloveButton(Icons.palette, 'COLOR', _cycleTheme),
          _buildGloveButton(Icons.assistant, 'GEMINI', _launchAssistant),
        ],
      ),
    );
  }

  Widget _buildGloveButton(IconData icon, String label, VoidCallback onPressed) {
    return SizedBox(
      width: 75,
      height: 75,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[900],
          foregroundColor: _accentColor,
          side: BorderSide(color: _accentColor, width: 2),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
