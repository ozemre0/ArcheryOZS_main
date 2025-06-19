import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:just_audio/just_audio.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  // Default timer settings
  int _prepDuration = 10;
  int _shootingDuration = 180;
  int _warningDuration = 30;
  bool _enableSound = true;
  
  // Timer state variables
  bool _isRunning = false;
  bool _isPaused = false;
  TimerPhase _currentPhase = TimerPhase.ready;
  int _currentSeconds = 0;
  
  // Audio players for different sounds
  final AudioPlayer _prepAudioPlayer = AudioPlayer();
  final AudioPlayer _shootingAudioPlayer = AudioPlayer();
  final AudioPlayer _finishAudioPlayer = AudioPlayer();
  
  // Get l10n instance
  late AppLocalizations l10n;
  
  // Storage for settings
  final _storage = const FlutterSecureStorage();
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSounds();
  }
  
  Future<void> _loadSounds() async {
    try {
      await _prepAudioPlayer.setAsset('assets/sounds/2times.MP3');
      await _shootingAudioPlayer.setAsset('assets/sounds/1time.MP3');
      await _finishAudioPlayer.setAsset('assets/sounds/3times.MP3');
    } catch (e) {
      debugPrint('Error loading sounds: $e');
    }
  }
  
  @override
  void dispose() {
    _prepAudioPlayer.dispose();
    _shootingAudioPlayer.dispose();
    _finishAudioPlayer.dispose();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    try {
      final prepTime = await _storage.read(key: 'timer_prep_time');
      final shootingTime = await _storage.read(key: 'timer_shooting_time');
      final warningTime = await _storage.read(key: 'timer_warning_time');
      final sound = await _storage.read(key: 'timer_sound');
      
      if (mounted) {
        setState(() {
          _prepDuration = prepTime != null ? int.tryParse(prepTime) ?? 10 : 10;
          _shootingDuration = shootingTime != null ? int.tryParse(shootingTime) ?? 180 : 180;
          _warningDuration = warningTime != null ? int.tryParse(warningTime) ?? 30 : 30;
          _enableSound = sound == null || sound == 'true'; // Default to true
        });
      }
    } catch (e) {
      // Silently fail and use defaults
    }
  }
  
  // Play sound based on phase
  Future<void> _playSound(TimerPhase phase) async {
    if (!_enableSound) return;
    
    try {
      switch(phase) {
        case TimerPhase.prep:
          await _prepAudioPlayer.seek(Duration.zero);
          await _prepAudioPlayer.play();
          break;
        case TimerPhase.shooting:
          await _shootingAudioPlayer.seek(Duration.zero);
          await _shootingAudioPlayer.play();
          break;
        case TimerPhase.finished:
          await _finishAudioPlayer.seek(Duration.zero);
          await _finishAudioPlayer.play();
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    l10n = AppLocalizations.of(context);
    
    // Determine the background color and text based on current timer phase
    Color backgroundColor;
    String statusText;
    
    switch (_currentPhase) {
      case TimerPhase.ready:
        backgroundColor = Colors.red;
        statusText = l10n.timerReady;
        break;
      case TimerPhase.prep:
        backgroundColor = Colors.red;
        statusText = l10n.prepPhase;
        break;
      case TimerPhase.shooting:
        backgroundColor = Colors.green;
        statusText = l10n.seriesPhase;
        break;
      case TimerPhase.warning:
        backgroundColor = Colors.orange;
        statusText = l10n.warningPhase;
        break;
      case TimerPhase.finished:
        backgroundColor = Colors.red;
        statusText = l10n.finished;
        break;
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.timerTitle),
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: _handleScreenTap,
        child: Container(
          color: backgroundColor,
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_currentPhase != TimerPhase.finished)
                  Center(
                    child: Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const SizedBox(height: 30),
                if (_currentPhase != TimerPhase.ready && _currentPhase != TimerPhase.finished)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Ekran genişliğinin %40'ını kaplayacak şekilde fontSize hesapla, max 80 olacak
                      double fontSize = constraints.maxWidth * 0.33;
                      if (fontSize > 80) fontSize = 80;
                      return Text(
                        _currentSeconds.toString(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: fontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                if (_currentPhase == TimerPhase.ready)
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      l10n.touchToStart,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (_currentPhase == TimerPhase.finished)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Ekran genişliğinin %80'ini kaplayacak şekilde fontSize hesapla, max 40 olacak
                      double fontSize = constraints.maxWidth * 0.08;
                      if (fontSize > 40) fontSize = 40;
                      return Center(
                        child: Text(
                          l10n.finished,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  void _handleScreenTap() {
    if (_currentPhase == TimerPhase.ready) {
      _startTimer();
    } else if (_currentPhase == TimerPhase.prep) {
      // Skip to shooting phase
      setState(() {
        _isRunning = true;
        _isPaused = false;
        _currentPhase = TimerPhase.shooting;
        _currentSeconds = _shootingDuration;
      });
      _playSound(TimerPhase.shooting);
    } else if (_currentPhase == TimerPhase.shooting) {
      // Skip to warning phase
      setState(() {
        _isRunning = true;
        _isPaused = false;
        _currentPhase = TimerPhase.warning;
        _currentSeconds = _warningDuration;
      });
    } else if (_currentPhase == TimerPhase.warning) {
      // Skip to finished phase
      setState(() {
        _currentPhase = TimerPhase.finished;
        _isRunning = false;
      });
      _playSound(TimerPhase.finished);
    } else if (_currentPhase == TimerPhase.finished) {
      // Reset back to ready
      setState(() {
        _currentPhase = TimerPhase.ready;
        _isRunning = false;
        _isPaused = false;
        _currentSeconds = 0;
      });
    }
  }
  
  void _startTimer() {
    setState(() {
      _isRunning = true;
      _isPaused = false;
      _currentPhase = TimerPhase.prep;
      _currentSeconds = _prepDuration;
    });
    _playSound(TimerPhase.prep);
    _tick();
  }
  
  void _tick() async {
    if (!mounted) return;
    
    while (_isRunning && _currentSeconds > 0) {
      if (!_isPaused) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() {
          _currentSeconds--;
        });
      } else {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    
    if (!mounted || !_isRunning) return;
    
    switch (_currentPhase) {
      case TimerPhase.prep:
        setState(() {
          _currentPhase = TimerPhase.shooting;
          _currentSeconds = _shootingDuration;
        });
        _playSound(TimerPhase.shooting);
        _tick();
        break;
      case TimerPhase.shooting:
        setState(() {
          _currentPhase = TimerPhase.warning;
          _currentSeconds = _warningDuration;
        });
        _tick();
        break;
      case TimerPhase.warning:
        setState(() {
          _currentPhase = TimerPhase.finished;
          _isRunning = false;
        });
        _playSound(TimerPhase.finished);
        break;
      default:
        break;
    }
  }
}

enum TimerPhase {
  ready,
  prep,
  shooting,
  warning,
  finished,
}
