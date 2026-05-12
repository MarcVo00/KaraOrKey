import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:app/config.dart';
import 'package:app/models/lyric_line.dart';

class TVPlayerScreen extends StatefulWidget {
  final String roomName;
  final String password;
  const TVPlayerScreen({super.key, required this.roomName, required this.password});
  @override
  State<TVPlayerScreen> createState() => _TVPlayerScreenState();
}

class _TVPlayerScreenState extends State<TVPlayerScreen> {
  late IO.Socket socket;
  late AudioPlayer _tvPlayer;
  List<LyricLine> lyrics = [];
  int currentLyricIndex = -1;
  String currentTitle = "Prêt à chanter !";
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1.0;
  bool _showVolumeBar = false;
  bool isReconnecting = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _tvPlayer = AudioPlayer();
    _initSocket();
    _tvPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        socket.emit('play_next');
        if (mounted) _resetPlaybackState();
      }
    });
    _tvPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _tvPlayer.positionStream.listen((p) {
      if (mounted) { setState(() => _position = p); _syncLyrics(p); }
    });
  }

  void _resetPlaybackState() {
    setState(() {
      lyrics = [];
      currentLyricIndex = -1;
      currentTitle = "Prêt à chanter !";
      _position = Duration.zero;
      _duration = Duration.zero;
    });
  }

  void _joinRoom() {
    socket.emit('join_karaoke_room', {
      'room': widget.roomName,
      'role': 'tv',
      'password': widget.password,
    });
  }

  void _initSocket() {
    socket = IO.io(
      baseUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );
    socket.connect();

    socket.onConnect((_) {
      if (mounted) setState(() => isReconnecting = false);
      _joinRoom();
    });

    socket.onDisconnect((_) {
      if (mounted) setState(() => isReconnecting = true);
    });

    socket.on('join_error', (data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message']), backgroundColor: Colors.red));
        Navigator.pop(context);
      }
    });

    socket.on('room_deleted', (_) {
      if (mounted) Navigator.pop(context);
    });

    socket.on('start_song', (data) => _startVisuals(data['id'], data['title']));
    socket.on('stop_song', (_) {
      if (mounted) { _resetPlaybackState(); _tvPlayer.stop(); }
    });
  }

  Future<void> _startVisuals(String songId, String title) async {
    setState(() { currentTitle = title; lyrics = []; currentLyricIndex = -1; });
    await _loadLyrics(songId);
    try {
      await _tvPlayer.stop();
      await _tvPlayer.setUrl('$baseUrl/api/play/$songId/audio');
      await _tvPlayer.setVolume(_volume);
      _tvPlayer.play();
    } catch (_) {}
  }

  Future<void> _loadLyrics(String songId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/play/$songId/lyrics'));
      if (response.statusCode == 200) {
        final lines = utf8.decode(response.bodyBytes).split('\n');
        final parsedLyrics = <LyricLine>[];
        final regExp = RegExp(r"^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)");
        for (var line in lines) {
          final match = regExp.firstMatch(line);
          if (match != null) {
            final text = match.group(4)!.trim();
            if (text.isNotEmpty) {
              final subsecStr = match.group(3)!;
              final ms = subsecStr.length == 2 ? int.parse(subsecStr) * 10 : int.parse(subsecStr);
              parsedLyrics.add(LyricLine(
                timestamp: Duration(
                  minutes: int.parse(match.group(1)!),
                  seconds: int.parse(match.group(2)!),
                  milliseconds: ms,
                ),
                text: text,
              ));
            }
          }
        }
        if (mounted) setState(() => lyrics = parsedLyrics);
      }
    } catch (_) {}
  }

  void _syncLyrics(Duration position) {
    if (lyrics.isEmpty) return;
    for (int i = 0; i < lyrics.length; i++) {
      final isLast = i == lyrics.length - 1;
      final isCurrent = isLast
          ? position >= lyrics[i].timestamp
          : position >= lyrics[i].timestamp && position < lyrics[i + 1].timestamp;
      if (isCurrent) {
        if (currentLyricIndex != i) setState(() => currentLyricIndex = i);
        break;
      }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() { socket.dispose(); _tvPlayer.dispose(); WakelockPlus.disable(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final currentLine = (lyrics.isNotEmpty && currentLyricIndex >= 0) ? lyrics[currentLyricIndex].text : "";
    final nextLine = (lyrics.isNotEmpty && currentLyricIndex >= 0 && currentLyricIndex + 1 < lyrics.length)
        ? lyrics[currentLyricIndex + 1].text : "";
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showVolumeBar = !_showVolumeBar),
        child: Stack(children: [
          Column(children: [
            // --- Titre + indicateur reconnexion ---
            Padding(
              padding: const EdgeInsets.only(top: 50.0, bottom: 8.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (isReconnecting) ...[
                  const SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                  const SizedBox(width: 8),
                  const Text("Reconnexion...", style: TextStyle(color: Colors.orange, fontSize: 12)),
                  const SizedBox(width: 16),
                ],
                Text(currentTitle,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              ]),
            ),

            // --- Barre de progression ---
            if (_duration > Duration.zero)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Column(children: [
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    color: const Color(0xFFE94560),
                    minHeight: 4,
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_fmt(_position), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    Text(_fmt(_duration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  ]),
                ]),
              ),
            const SizedBox(height: 12),

            // --- Zone paroles ---
            Expanded(
              child: lyrics.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.music_note, size: 80, color: Colors.white24),
                      const SizedBox(height: 20),
                      Text("En attente du DJ...", style: TextStyle(color: Colors.grey[600], fontSize: 24)),
                    ]))
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
                                  .animate(animation),
                              child: child,
                            ),
                          ),
                          child: Text(
                            currentLine,
                            key: ValueKey<String>('current_$currentLine'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 48, fontWeight: FontWeight.bold,
                              color: Color(0xFFE94560),
                              shadows: [Shadow(blurRadius: 15, color: Color(0xFFE94560))],
                            ),
                          ),
                        ),
                        const SizedBox(height: 50),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Text(
                            nextLine,
                            key: ValueKey<String>('next_$nextLine'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 32, color: Colors.white30),
                          ),
                        ),
                      ]),
                    ),
            ),
          ]),

          // --- Panneau volume (apparaît au tap sur l'écran) ---
          if (_showVolumeBar)
            Positioned(
              bottom: 30, left: 60, right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(children: [
                  const Icon(Icons.volume_down, color: Colors.white54),
                  Expanded(
                    child: Slider(
                      value: _volume,
                      min: 0, max: 1,
                      activeColor: const Color(0xFFE94560),
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        setState(() => _volume = v);
                        _tvPlayer.setVolume(v);
                      },
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.white54),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
