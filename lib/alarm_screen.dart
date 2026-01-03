import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

class AlarmScreen extends StatefulWidget {
  final String missionMessage;

  const AlarmScreen({super.key, required this.missionMessage});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
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
    // Close the screen
    if (mounted) {
      Navigator.of(context).pop();
    }
    // TODO: Send acknowledgment to server here
    print("User acknowledged the alert.");
  }

  @override
  void dispose() {
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
