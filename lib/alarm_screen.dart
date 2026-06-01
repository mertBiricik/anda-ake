/// Alarm Screen — Nuclear alarm UI with full system takeover
///
/// Safety-Critical Features:
/// - WakeLock: Prevents screen from turning off
/// - Max Volume: Forces device volume to 100%
/// - Alarm Audio Stream: Bypasses DND/silent mode
/// - Continuous Loop: Sound plays until ACKNOWLEDGE is pressed
/// - ACK feedback: Sends acknowledgment back to server
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
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  double? _originalVolume;
  late AnimationController _flashController;
  late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();

    // Flashing animation for urgency
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _flashAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
    );

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

  @override
  void dispose() {
    _flashController.dispose();
    WakelockPlus.disable();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _flashAnimation,
          builder: (context, child) {
            return Container(
              color: Color.lerp(
                Colors.red.shade900,
                Colors.black,
                1.0 - _flashAnimation.value,
              ),
              child: child,
            );
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Alarm image
              Image.asset('assets/alarm_image.png', height: 120),
              const SizedBox(height: 40),
              const Text(
                "🚨 CRITICAL MISSION 🚨",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  widget.missionMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
              if (widget.alarmId != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Mission: ${widget.alarmId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const Spacer(),
              // Acknowledge button
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 80,
                  child: ElevatedButton(
                    onPressed: _acknowledgeAndStop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      "ACKNOWLEDGE",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
