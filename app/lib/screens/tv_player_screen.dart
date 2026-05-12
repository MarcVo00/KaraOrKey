import 'dart:async';
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
  bool _isPaused = false;
  bool isReconnecting = false;
  List<dynamic> _queue = [];
  bool _isDragging = false;
  double _dragPosition = 0.0;

  Timer? _syncTimer;

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
      if (mounted && !_isDragging) { setState(() => _position = p); _syncLyrics(p); }
    });

    // Émet la position toutes les 5s pour permettre la correction de drift côté DJ
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) socket.emit('position_sync', {'position_ms': _position.inMilliseconds});
    });
  }

  void _resetPlaybackState() {
    setState(() {
      lyrics = []; currentLyricIndex = -1;
      currentTitle = "Prêt à chanter !";
      _position = Duration.zero; _duration = Duration.zero;
      _isPaused = false;
    });
  }

  void _joinRoom() => socket.emit('join_karaoke_room', {
    'room': widget.roomName, 'role': 'tv', 'password': widget.password,
  });

  void _initSocket() {
    socket = IO.io(baseUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(10)
        .setReconnectionDelay(2000)
        .build());
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
    socket.on('room_deleted', (_) { if (mounted) Navigator.pop(context); });

    socket.on('sync_state', (data) {
      if (mounted) setState(() {
        _queue = List<dynamic>.from(data['queue'] ?? []);
        _isPaused = data['paused'] ?? false;
      });
    });

    socket.on('start_song', (data) {
      setState(() => _isPaused = false);
      _startVisuals(data['id'], data['title']);
    });

    socket.on('stop_song', (_) {
      if (mounted) { _resetPlaybackState(); _tvPlayer.stop(); }
    });

    socket.on('pause_song', (_) {
      _tvPlayer.pause();
      if (mounted) setState(() => _isPaused = true);
    });

    socket.on('resume_song', (_) {
      _tvPlayer.play();
      if (mounted) setState(() => _isPaused = false);
    });

    socket.on('seek_to', (data) {
      final ms = (data['position_ms'] as num?)?.toInt() ?? 0;
      _tvPlayer.seek(Duration(milliseconds: ms));
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
        final parsed = <LyricLine>[];
        final re = RegExp(r"^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)");
        for (final line in lines) {
          final m = re.firstMatch(line);
          if (m != null) {
            final text = m.group(4)!.trim();
            if (text.isNotEmpty) {
              final sub = m.group(3)!;
              final ms = sub.length == 2 ? int.parse(sub) * 10 : int.parse(sub);
              parsed.add(LyricLine(
                timestamp: Duration(minutes: int.parse(m.group(1)!),
                    seconds: int.parse(m.group(2)!), milliseconds: ms),
                text: text,
              ));
            }
          }
        }
        if (mounted) setState(() => lyrics = parsed);
      }
    } catch (_) {}
  }

  void _syncLyrics(Duration position) {
    if (lyrics.isEmpty) return;
    for (int i = 0; i < lyrics.length; i++) {
      final isLast = i == lyrics.length - 1;
      final ok = isLast
          ? position >= lyrics[i].timestamp
          : position >= lyrics[i].timestamp && position < lyrics[i + 1].timestamp;
      if (ok) { if (currentLyricIndex != i) setState(() => currentLyricIndex = i); break; }
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    socket.dispose();
    _tvPlayer.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentLine = (lyrics.isNotEmpty && currentLyricIndex >= 0) ? lyrics[currentLyricIndex].text : "";
    final nextLine = (lyrics.isNotEmpty && currentLyricIndex >= 0 && currentLyricIndex + 1 < lyrics.length)
        ? lyrics[currentLyricIndex + 1].text : "";
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final displayProgress = _isDragging ? _dragPosition : progress;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Quitter l'écran TV ?"),
            content: const Text("La salle n'aura plus d'écran TV. Continuer ?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Quitter", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if ((confirm ?? false) && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showVolumeBar = !_showVolumeBar),
        child: Stack(children: [
          Column(children: [

            // --- Titre + indicateurs ---
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
                if (_isPaused)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.pause_circle_outline, color: Colors.white38, size: 22),
                  ),
                Text(currentTitle,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              ]),
            ),

            // --- Barre de progression (seek) ---
            if (_duration > Duration.zero)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: Column(children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      activeTrackColor: _isPaused ? Colors.white38 : const Color(0xFFE94560),
                      inactiveTrackColor: Colors.white12,
                      thumbColor: _isPaused ? Colors.white38 : const Color(0xFFE94560),
                      overlayColor: const Color(0xFFE94560).withOpacity(0.2),
                    ),
                    child: Slider(
                      value: displayProgress,
                      min: 0, max: 1,
                      onChangeStart: (v) => setState(() { _isDragging = true; _dragPosition = v; }),
                      onChanged: (v) => setState(() => _dragPosition = v),
                      onChangeEnd: (v) {
                        setState(() => _isDragging = false);
                        final ms = (v * _duration.inMilliseconds).round();
                        socket.emit('command_seek', {'position_ms': ms});
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_fmt(_isDragging
                              ? Duration(milliseconds: (_dragPosition * _duration.inMilliseconds).round())
                              : _position),
                          style: const TextStyle(color: Colors.white38, fontSize: 12)),
                      Text(_fmt(_duration), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 12),

            // --- Zone paroles / écran attente ---
            Expanded(
              child: lyrics.isEmpty
                  ? _buildWaitingScreen()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40.0),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, anim) => FadeTransition(opacity: anim,
                              child: SlideTransition(
                                  position: Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
                                      .animate(anim), child: child)),
                          child: Text(currentLine,
                              key: ValueKey<String>('cur_$currentLine'),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold,
                                  color: _isPaused ? Colors.white38 : const Color(0xFFE94560),
                                  shadows: _isPaused ? [] : const [
                                    Shadow(blurRadius: 15, color: Color(0xFFE94560))
                                  ])),
                        ),
                        const SizedBox(height: 50),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                          child: Text(nextLine,
                              key: ValueKey<String>('nxt_$nextLine'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 32, color: Colors.white30)),
                        ),
                      ]),
                    ),
            ),
          ]),

          // --- Panneau volume (tap pour afficher) ---
          if (_showVolumeBar)
            Positioned(
              bottom: 30, left: 60, right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87, borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(children: [
                  const Icon(Icons.volume_down, color: Colors.white54),
                  Expanded(child: Slider(
                    value: _volume, min: 0, max: 1,
                    activeColor: const Color(0xFFE94560), inactiveColor: Colors.white24,
                    onChanged: (v) { setState(() => _volume = v); _tvPlayer.setVolume(v); },
                  )),
                  const Icon(Icons.volume_up, color: Colors.white54),
                ]),
              ),
            ),
        ]),
      ),
      ), // PopScope
    );
  }

  Widget _buildWaitingScreen() {
    if (_queue.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.music_note, size: 80, color: Colors.white24),
        const SizedBox(height: 20),
        Text("En attente du DJ...", style: TextStyle(color: Colors.grey[600], fontSize: 24)),
      ]));
    }

    // File d'attente visible quand aucune chanson ne joue
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text("À venir", style: TextStyle(color: Colors.grey[600], fontSize: 18, letterSpacing: 3)),
      const SizedBox(height: 30),
      ..._queue.take(5).toList().asMap().entries.map((e) {
        final isFirst = e.key == 0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: isFirst ? const Color(0xFFE94560).withOpacity(0.15) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFirst ? const Color(0xFFE94560).withOpacity(0.5) : Colors.white12,
            ),
          ),
          child: Row(children: [
            Icon(isFirst ? Icons.play_arrow : Icons.queue_music,
                color: isFirst ? const Color(0xFFE94560) : Colors.white38, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(e.value['title'],
                style: TextStyle(
                    fontSize: isFirst ? 20 : 16,
                    color: isFirst ? Colors.white : Colors.white54,
                    fontWeight: isFirst ? FontWeight.bold : FontWeight.normal),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        );
      }),
      if (_queue.length > 5)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text("+ ${_queue.length - 5} autres",
              style: TextStyle(color: Colors.grey[700], fontSize: 14)),
        ),
    ]);
  }
}
