import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:audio_session/audio_session.dart';

class AlarmScreen extends StatefulWidget {
  final String missionMessage;

  const AlarmScreen({super.key, required this.missionMessage});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  double? _originalVolume;

  @override
  void initState() {
    super.initState();
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
      print("Error controlling volume: $e");
    }

    // 3. Configure Audio Session for Alarm (Bypasses some DND settings)
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        flags: AndroidAudioFlags.audibilityEnforced, // Critical for alarm
        usage: AndroidAudioUsage.alarm, // Critical: Uses Alarm Stream
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransientMayDuck,
      androidWillPauseWhenDucked: false,
    ));

    _startAlarm();
  }

  void _startAlarm() async {
    // Loop the sound continuously
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    // Play the sound from assets
    await _audioPlayer.play(AssetSource('sounds/alarm.mp3'));
  }

  void _acknowledgeAndStop() async {
    // Stop the sound
    await _audioPlayer.stop();
    
    // Release control
    await WakelockPlus.disable();
    if (_originalVolume != null) {
      // Create a slight delay to ensure sound stops before volume drops (optional, but good UX)
      await FlutterVolumeController.setVolume(_originalVolume!);
    }

    // Close the screen
    if (mounted) {
      Navigator.of(context).pop();
    }
    // TODO: Send acknowledgment to server here
    print("User acknowledged the alert.");
  }

  @override
  void dispose() {
    // Safety net: ensure controls are released if screen is killed
    WakelockPlus.disable();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900, // Urgent background color
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Flashing Image (Static for now)
            Image.asset('assets/alarm_image.png', height: 120),
            const SizedBox(height: 40),
            const Text(
              "CRITICAL MISSION",
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                widget.missionMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 80,
              child: ElevatedButton(
                onPressed: _acknowledgeAndStop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                ),
                child: const Text("ACKNOWLEDGE", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
