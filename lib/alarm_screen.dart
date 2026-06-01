/// Alarm Screen — Nuclear alarm UI with full system takeover
///
/// Safety-Critical Features:
/// - WakeLock: Prevents screen from turning off
/// - Max Volume: Forces device volume to 100%
/// - Alarm Audio Stream: Bypasses DND/silent mode
/// - Continuous Loop: Sound plays until ACKNOWLEDGE is pressed
/// - ACK feedback: Sends acknowledgment back to server
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:audio_session/audio_session.dart';

class AlarmScreen extends StatefulWidget {
  final String missionMessage;
  final String? alarmId;
  final void Function(String alarmId)? onAcknowledge;

  const AlarmScreen({
    super.key,
    required this.missionMessage,
    this.alarmId,
    this.onAcknowledge,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  double? _originalVolume;
  late AnimationController _flashController;
  late AnimationController _borderPulse;
  late Animation<double> _flashAnimation;
  late Animation<double> _borderAnimation;
  Timer? _elapsedTimer;
  int _elapsedSeconds = 0;
  final DateTime _alarmTime = DateTime.now();

  @override
  void initState() {
    super.initState();

    // Flash animation — alternating red/black for urgency
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _flashAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
    );

    // Border pulse animation
    _borderPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _borderAnimation = Tween<double>(begin: 1.0, end: 3.0).animate(
      CurvedAnimation(parent: _borderPulse, curve: Curves.easeInOut),
    );

    // Elapsed timer
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });

    _takeControl();
  }

  void _takeControl() async {
    // 1. Keep screen on (Nuclear)
    await WakelockPlus.enable();

    // 2. Maximize Volume (Nuclear)
    try {
      _originalVolume = await FlutterVolumeController.getVolume();
      await FlutterVolumeController.setVolume(1.0);
    } catch (e) {
      debugPrint("Error controlling volume: $e");
    }

    // 3. Configure Audio Session for Alarm (Bypasses some DND settings)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.audibilityEnforced,
        usage: AndroidAudioUsage.alarm,
      ),
      androidAudioFocusGainType:
          AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));

    _startAlarm();
  }

  void _startAlarm() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
  }

  void _acknowledgeAndStop() async {
    // Stop the sound
    await _audioPlayer.stop();

    // Release control
    await WakelockPlus.disable();
    if (_originalVolume != null) {
      await FlutterVolumeController.setVolume(_originalVolume!);
    }

    // Send acknowledgment to server
    if (widget.alarmId != null && widget.onAcknowledge != null) {
      widget.onAcknowledge!(widget.alarmId!);
    }

    debugPrint("User acknowledged the alert: ${widget.alarmId}");

    // Close the screen
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  String _formatElapsed() {
    final m = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '+$m:$s';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _flashController.dispose();
    _borderPulse.dispose();
    _elapsedTimer?.cancel();
    WakelockPlus.disable();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: _flashAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(const Color(0xFF0A0000), const Color(0xFF3D0000), _flashAnimation.value)!,
                  const Color(0xFF050000),
                  Color.lerp(const Color(0xFF0A0000), const Color(0xFF3D0000), _flashAnimation.value)!,
                ],
              ),
            ),
            child: child,
          );
        },
        child: SafeArea(
          child: Column(
            children: [
              // ── Top Info Bar ──
              _buildTopBar(),
              const Spacer(flex: 1),
              // ── Warning Icon ──
              AnimatedBuilder(
                animation: _flashAnimation,
                builder: (context, _) {
                  return Icon(
                    Icons.warning_amber_rounded,
                    size: 100,
                    color: Color.lerp(const Color(0xFFFF1744), Colors.white, _flashAnimation.value),
                    shadows: [
                      Shadow(color: const Color(0xFFFF1744).withOpacity(0.8), blurRadius: 30),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // ── Title ──
              const Text(
                'KRİTİK GÖREV',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w900,
                  color: Colors.white, letterSpacing: 6.0,
                  fontFamily: 'monospace',
                  shadows: [Shadow(color: Color(0xFFFF1744), blurRadius: 20)],
                ),
              ),
              const SizedBox(height: 8),
              AnimatedBuilder(
                animation: _borderAnimation,
                builder: (context, _) {
                  return Container(
                    height: 2,
                    width: 200,
                    color: Colors.redAccent.withOpacity(0.3 + 0.4 * _flashAnimation.value),
                  );
                },
              ),
              const SizedBox(height: 24),
              // ── Mission Message ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.4), width: 1.5),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF1744).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text('GELEN BİLDİRİM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFFF1744), letterSpacing: 1.5)),
                        ),
                        const Spacer(),
                        Text(_formatTime(_alarmTime), style: const TextStyle(fontSize: 10, color: Colors.white38, fontFamily: 'monospace')),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.missionMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold,
                        color: Colors.white, height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.alarmId != null) ...[
                const SizedBox(height: 16),
                Text(
                  'OP_ID: ${widget.alarmId}',
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.4), fontFamily: 'monospace', letterSpacing: 2.0,
                  ),
                ),
              ],
              const Spacer(flex: 2),
              // ── ACK Button ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimatedBuilder(
                  animation: _borderAnimation,
                  builder: (context, child) {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.1 + 0.05 * _borderAnimation.value),
                            blurRadius: 10 * _borderAnimation.value,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: child,
                    );
                  },
                  child: SizedBox(
                    width: double.infinity,
                    height: 80,
                    child: ElevatedButton(
                      onPressed: _acknowledgeAndStop,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFC62828),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 32),
                          SizedBox(width: 12),
                          Text('ONAYLA VE SUSTUR', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 3.0)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF1744),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFFF1744).withOpacity(0.8), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 8),
              const Text('NÜKLEER ALARM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFFF1744), letterSpacing: 1.5, fontFamily: 'monospace')),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF1744).withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'GEÇEN SÜRE ${_formatElapsed()}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFFF1744), fontFamily: 'monospace', letterSpacing: 1.0),
            ),
          ),
        ],
      ),
    );
  }
}
