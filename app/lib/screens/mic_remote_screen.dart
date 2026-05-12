import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:just_audio/just_audio.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/config.dart';
import 'package:app/models/lyric_line.dart';
import 'package:app/widgets/youtube_search_dialog.dart';
import 'package:app/services/web_mic_stub.dart'
    if (dart.library.html) 'package:app/services/web_mic.dart';

class MicRemoteScreen extends StatefulWidget {
  final String roomName;
  final String password;
  const MicRemoteScreen({super.key, required this.roomName, required this.password});
  @override
  State<MicRemoteScreen> createState() => _MicRemoteScreenState();
}

class _MicRemoteScreenState extends State<MicRemoteScreen> {
  late IO.Socket socket;

  // --- Audio local ---
  late AudioPlayer _localPlayer;
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _micOutput = PlayerStream();
  bool isMicOn = false;
  StreamSubscription? _micSubscription;
  double _musicVolume = 1.0;
  bool _showVolumeBar = false;

  // --- Mode chanteur ---
  bool _isSinging = true;
  int _lastKnownTvPositionMs = 0;

  // --- Paroles + progression ---
  List<LyricLine> _lyrics = [];
  int _lyricIndex = -1;
  bool _isPaused = false;
  Duration _songPosition = Duration.zero;
  Duration _songDuration = Duration.zero;
  bool _isDragging = false;
  double _dragPosition = 0.0;

  // --- Décalage paroles (user offset, en ms) ---
  // Positif = paroles décalées vers la droite (apparaissent plus tard)
  // Négatif = paroles décalées vers la gauche (apparaissent plus tôt)
  int _lyricsOffsetMs = 0;
  String? _currentSongId; // pour sauvegarder l'offset par chanson

  // --- Favoris ---
  Set<String> _favorites = {};
  bool _showFavoritesOnly = false;

  // --- Historique session ---
  final List<Map<String, dynamic>> _history = [];

  // --- État de la salle ---
  bool isReconnecting = false;
  List<dynamic> allSongs = [];
  List<dynamic> activeDownloads = [];
  bool isLoading = true;
  Map<String, dynamic>? currentSong;
  List<Map<String, dynamic>> queue = [];

  final TextEditingController _localTitleController = TextEditingController();
  final TextEditingController _localArtistController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _localPlayer = AudioPlayer();
    _localPlayer.positionStream.listen((pos) {
      if (mounted && !_isDragging) { setState(() => _songPosition = pos); _syncLyrics(pos); }
    });
    _localPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _songDuration = d);
    });
    _localPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() {
          _lyrics = []; _lyricIndex = -1; _isPaused = false;
          _songPosition = Duration.zero; _songDuration = Duration.zero;
        });
      }
    });
    _loadFavorites();
    _initSocket();
    _initAudio();
    _fetchSongs();
    _localTitleController.addListener(() => setState(() {}));
    _localArtistController.addListener(() => setState(() {}));
  }

  // ==========================================
  // FAVORIS
  // ==========================================

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorites') ?? [];
    if (mounted) setState(() => _favorites = Set.from(list));
  }

  Future<void> _toggleFavorite(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favorites.contains(songId)) _favorites.remove(songId);
      else _favorites.add(songId);
    });
    await prefs.setStringList('favorites', _favorites.toList());
  }

  // ==========================================
  // HISTORIQUE
  // ==========================================

  void _addToHistory(Map<String, dynamic> song) {
    // On n'ajoute pas de doublon si la chanson est déjà en tête de liste
    if (_history.isEmpty || _history.first['id'] != song['id']) {
      setState(() => _history.insert(0, Map.from(song)));
    }
  }

  void _showHistorySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text("Chansons jouées",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const Divider(color: Colors.white24, height: 1),
        Expanded(
          child: _history.isEmpty
              ? const Center(child: Text("Aucune chanson jouée pour l'instant.",
                  style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _history.length,
                  itemBuilder: (ctx, i) {
                    final isPlaying = currentSong != null &&
                        _history[i]['id'] == currentSong!['id'];
                    return ListTile(
                      leading: Icon(
                        isPlaying ? Icons.play_circle : Icons.history,
                        color: isPlaying ? Colors.pinkAccent : Colors.white38,
                      ),
                      title: Text(_history[i]['title'],
                          style: TextStyle(
                              color: isPlaying ? Colors.white : Colors.white70,
                              fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal)),
                      trailing: isPlaying
                          ? const Text("En cours",
                              style: TextStyle(color: Colors.pinkAccent, fontSize: 12))
                          : null,
                    );
                  },
                ),
        ),
      ]),
    );
  }

  // ==========================================
  // OFFSET PAROLES
  // ==========================================

  Future<void> _loadLyricsOffset(String songId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt('lyrics_offset_$songId') ?? 0;
    if (mounted) setState(() => _lyricsOffsetMs = saved);
  }

  Future<void> _adjustOffset(int deltaMs) async {
    final newOffset = _lyricsOffsetMs + deltaMs;
    setState(() => _lyricsOffsetMs = newOffset);
    if (_currentSongId != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lyrics_offset_$_currentSongId', newOffset);
    }
  }

  // ==========================================
  // SOCKET
  // ==========================================

  void _joinRoom() => socket.emit('join_karaoke_room', {
    'room': widget.roomName, 'role': 'dj', 'password': widget.password,
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
    socket.on('room_deleted', (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("La salle a été fermée !"), backgroundColor: Colors.orange));
        Navigator.pop(context);
      }
    });

    socket.on('sync_state', (data) {
      if (!mounted) return;
      final prevSong = currentSong;
      setState(() {
        currentSong = data['current_song'];
        queue = List<Map<String, dynamic>>.from(data['queue']);
        _isPaused = data['paused'] ?? false;
      });
      if (_isSinging && currentSong != null && prevSong == null &&
          _localPlayer.processingState == ProcessingState.idle) {
        _startLocalPlayback(currentSong!['id'], currentSong!['title'],
            seekMs: _lastKnownTvPositionMs);
      }
    });

    socket.on('start_song', (data) {
      if (mounted) {
        setState(() => _isPaused = false);
        // La chanson qui COMMENCE va dans l'historique
        _addToHistory(Map<String, dynamic>.from(data));
      }
      if (_isSinging) _startLocalPlayback(data['id'], data['title']);
    });

    socket.on('stop_song', (_) {
      _localPlayer.stop();
      if (mounted) setState(() {
        _lyrics = []; _lyricIndex = -1; _isPaused = false;
        _songPosition = Duration.zero; _songDuration = Duration.zero;
      });
    });
    socket.on('pause_song', (_) {
      _localPlayer.pause();
      if (mounted) setState(() => _isPaused = true);
    });
    socket.on('resume_song', (_) {
      _localPlayer.play();
      if (mounted) setState(() => _isPaused = false);
    });
    socket.on('seek_to', (data) async {
      final ms = (data['position_ms'] as num?)?.toInt() ?? 0;
      if (_isSinging) await _localPlayer.seek(Duration(milliseconds: ms));
    });
    socket.on('position_sync', (data) async {
      _lastKnownTvPositionMs = (data['position_ms'] as num?)?.toInt() ?? 0;
      if (!_isSinging) return;
      final myMs = _localPlayer.position.inMilliseconds;
      if ((_lastKnownTvPositionMs - myMs).abs() > 500 &&
          _localPlayer.playing &&
          _localPlayer.processingState == ProcessingState.ready) {
        await _localPlayer.seek(Duration(milliseconds: _lastKnownTvPositionMs));
      }
    });
    socket.on('download_progress', (data) {
      if (mounted) setState(() { if (data is List) activeDownloads = data; });
    });
    socket.on('download_error', (data) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: Colors.red,
              duration: const Duration(seconds: 5)));
    });
    socket.on('library_updated', (_) {
      _fetchSongs();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("🎉 Karaoké prêt !")));
    });
  }

  // ==========================================
  // LECTURE LOCALE + PAROLES
  // ==========================================

  Future<void> _startLocalPlayback(String songId, String title, {int seekMs = 0}) async {
    _currentSongId = songId;
    if (mounted) setState(() { _lyrics = []; _lyricIndex = -1; });
    await Future.wait([_loadLyrics(songId), _loadLyricsOffset(songId)]);
    try {
      await _localPlayer.stop();
      await _localPlayer.setUrl('$baseUrl/api/play/$songId/audio');
      if (seekMs > 0) await _localPlayer.seek(Duration(milliseconds: seekMs));
      await _localPlayer.setVolume(_musicVolume);
      _localPlayer.play();
    } catch (_) {}
  }

  Future<void> _loadLyrics(String songId) async {
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/play/$songId/lyrics'));
      if (r.statusCode != 200) return;
      final lines = utf8.decode(r.bodyBytes).split('\n');

      // Lire le tag [offset:X] standard du format LRC
      int lrcTagOffsetMs = 0;
      final offsetTagRe = RegExp(r'^\[offset:([+-]?\d+)\]');
      for (final line in lines) {
        final m = offsetTagRe.firstMatch(line.trim());
        if (m != null) { lrcTagOffsetMs = int.tryParse(m.group(1)!) ?? 0; break; }
      }

      final parsed = <LyricLine>[];
      final re = RegExp(r"^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)");
      for (final line in lines) {
        final m = re.firstMatch(line);
        if (m != null) {
          final text = m.group(4)!.trim();
          if (text.isNotEmpty) {
            final sub = m.group(3)!;
            final rawMs = sub.length == 2 ? int.parse(sub) * 10 : int.parse(sub);
            final baseMs = Duration(
              minutes: int.parse(m.group(1)!),
              seconds: int.parse(m.group(2)!),
              milliseconds: rawMs,
            ).inMilliseconds;
            // Applique le tag LRC ; le user offset est appliqué dans _syncLyrics
            final adjusted = (baseMs + lrcTagOffsetMs).clamp(0, 99999999);
            parsed.add(LyricLine(
              timestamp: Duration(milliseconds: adjusted),
              text: text,
            ));
          }
        }
      }
      if (mounted) setState(() => _lyrics = parsed);
    } catch (_) {}
  }

  void _syncLyrics(Duration position) {
    if (_lyrics.isEmpty) return;
    // Le user offset décale la position de lecture : si offset > 0, les paroles
    // apparaissent plus tard (on avance artificiellement la position comparée)
    final effectivePos = Duration(milliseconds:
        (position.inMilliseconds - _lyricsOffsetMs).clamp(0, 99999999));
    for (int i = 0; i < _lyrics.length; i++) {
      final isLast = i == _lyrics.length - 1;
      final ok = isLast
          ? effectivePos >= _lyrics[i].timestamp
          : effectivePos >= _lyrics[i].timestamp && effectivePos < _lyrics[i + 1].timestamp;
      if (ok) { if (_lyricIndex != i) setState(() => _lyricIndex = i); break; }
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ==========================================
  // MODE "JE CHANTE"
  // ==========================================

  void _toggleSinging() {
    setState(() => _isSinging = !_isSinging);
    if (_isSinging) {
      if (currentSong != null && !_isPaused) {
        _startLocalPlayback(currentSong!['id'], currentSong!['title'],
            seekMs: _lastKnownTvPositionMs);
      }
    } else {
      _localPlayer.stop();
      setState(() {
        _lyrics = []; _lyricIndex = -1; _songPosition = Duration.zero;
      });
    }
  }

  // ==========================================
  // MICRO
  // ==========================================

  Future<void> _initAudio() async {
    try { await _recorder.initialize(); await _micOutput.initialize(); } catch (_) {}
  }

  Future<void> _toggleMic() async {
    if (isMicOn) {
      if (kIsWeb) {
        WebMic.stop();
      } else {
        _micSubscription?.cancel();
        await _recorder.stop();
      }
      setState(() => isMicOn = false);
    } else {
      if (kIsWeb) {
        final ok = await WebMic.start();
        if (ok) setState(() => isMicOn = true);
      } else {
        if (await Permission.microphone.request().isGranted) {
          await _micOutput.start();
          await _recorder.start();
          _micSubscription = _recorder.audioStream.listen((d) => _micOutput.writeChunk(d));
          setState(() => isMicOn = true);
        }
      }
    }
  }

  // ==========================================
  // CONTRÔLES DJ
  // ==========================================

  Future<void> _fetchSongs() async {
    if (!mounted) return;
    try {
      final r = await http.get(Uri.parse('$baseUrl/api/songs')).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200 && mounted) setState(() { allSongs = json.decode(r.body); isLoading = false; });
    } catch (_) { if (mounted) setState(() => isLoading = false); }
  }

  void _handleSongTap(dynamic song) {
    if (currentSong == null) {
      socket.emit('command_play', song);
    } else {
      socket.emit('add_to_queue', song);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("🎵 Ajouté : ${song['title']}")));
    }
  }

  void _togglePause() => socket.emit(_isPaused ? 'command_resume' : 'command_pause');

  void _stopSong() {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Arrêter la chanson ?"),
      content: Text("Arrêter « ${currentSong!['title']} » ?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () { Navigator.pop(context); socket.emit('command_stop'); },
          child: const Text("Arrêter", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  void _playNext() => socket.emit('play_next');
  void _removeFromQueue(int i) => socket.emit('remove_from_queue', {'index': i});

  Future<void> _triggerDownload(String url, String title) async {
    // Protection contre les doublons
    if (activeDownloads.any((dl) => dl['title'] == title)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ce titre est déjà en cours de traitement.")));
      return;
    }
    if (allSongs.any((s) => s['id'] == title)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ce titre est déjà dans la bibliothèque.")));
      return;
    }
    try {
      await http.post(Uri.parse('$baseUrl/api/add_youtube'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"url": url, "title": title}));
    } catch (_) {}
  }

  Future<void> _cancelDownload(String taskId) async {
    try {
      await http.post(Uri.parse('$baseUrl/api/cancel'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"task_id": taskId}));
    } catch (_) {}
  }

  void _confirmDeleteSong(dynamic song) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Supprimer la chanson ?"),
      content: Text("Supprimer définitivement « ${song['title']} » ?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            Navigator.pop(context);
            try {
              final res = await http.post(Uri.parse('$baseUrl/api/delete_song'),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({"song_id": song['id']}));
              if (res.statusCode == 200) {
                _fetchSongs();
                _favorites.remove(song['id']);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("🗑️ ${song['title']} supprimée.")));
              } else {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Erreur lors de la suppression."),
                        backgroundColor: Colors.red));
              }
            } catch (_) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Impossible de joindre le serveur."),
                      backgroundColor: Colors.red));
            }
          },
          child: const Text("Supprimer", style: TextStyle(color: Colors.white)),
        ),
      ],
    ));
  }

  // ==========================================
  // DISPOSE & FILTRES
  // ==========================================

  @override
  void dispose() {
    socket.dispose();
    _localPlayer.dispose();
    _micSubscription?.cancel();
    _recorder.stop(); _micOutput.stop();
    _localTitleController.dispose(); _localArtistController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  List<dynamic> get filteredSongs {
    final t = _localTitleController.text.toLowerCase();
    final a = _localArtistController.text.toLowerCase();
    return allSongs.where((song) {
      if (_showFavoritesOnly && !_favorites.contains(song['id'])) return false;
      final title = song['title'].toString().toLowerCase();
      final parts = title.split(' - ');
      final titlePart = parts.length > 1 ? parts.sublist(1).join(' - ') : title;
      return titlePart.contains(t) && parts[0].contains(a);
    }).toList();
  }

  // ==========================================
  // BUILD
  // ==========================================

  @override
  Widget build(BuildContext context) {
    final currentLine = (_lyrics.isNotEmpty && _lyricIndex >= 0) ? _lyrics[_lyricIndex].text : "";
    final nextLine = (_lyrics.isNotEmpty && _lyricIndex >= 0 && _lyricIndex + 1 < _lyrics.length)
        ? _lyrics[_lyricIndex + 1].text : "";

    return Scaffold(
      appBar: AppBar(
        title: Text("DJ - ${widget.roomName}"),
        actions: [
          if (isReconnecting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                SizedBox(width: 6),
                Text("Reconnexion...", style: TextStyle(fontSize: 12, color: Colors.orange)),
              ]),
            ),
          IconButton(
            icon: Badge(
              isLabelVisible: _history.isNotEmpty,
              label: Text('${_history.length}', style: const TextStyle(fontSize: 10)),
              child: const Icon(Icons.history),
            ),
            onPressed: _showHistorySheet,
            tooltip: "Historique",
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _toggleSinging,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _isSinging ? const Color(0xFFE94560).withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _isSinging ? const Color(0xFFE94560) : Colors.white24),
                ),
                child: Row(children: [
                  Icon(Icons.mic, size: 14,
                      color: _isSinging ? const Color(0xFFE94560) : Colors.white38),
                  const SizedBox(width: 4),
                  Text("Je chante",
                      style: TextStyle(fontSize: 12,
                          color: _isSinging ? const Color(0xFFE94560) : Colors.white38)),
                ]),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pink,
        onPressed: () => showDialog(context: context,
            builder: (_) => YoutubeSearchDialog(onDownload: _triggerDownload)),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [

        // --- Monitor paroles + seek + offset ---
        if (currentSong != null && _isSinging)
          Container(
            width: double.infinity,
            color: const Color(0xFF0D0D1A),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Column(children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  currentLine.isEmpty ? "♪" : currentLine,
                  key: ValueKey<String>('dj_cur_$currentLine'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                      color: currentLine.isEmpty || _isPaused
                          ? Colors.white24 : const Color(0xFFE94560)),
                ),
              ),
              if (nextLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(nextLine, key: ValueKey<String>('dj_nxt_$nextLine'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Colors.white38)),
                ),
              ],
              if (_songDuration > Duration.zero) ...[
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    activeTrackColor: _isPaused ? Colors.white24 : const Color(0xFFE94560),
                    inactiveTrackColor: Colors.white10,
                    thumbColor: _isPaused ? Colors.white24 : const Color(0xFFE94560),
                    overlayColor: const Color(0xFFE94560).withOpacity(0.15),
                  ),
                  child: Slider(
                    value: _isDragging ? _dragPosition
                        : (_songDuration.inMilliseconds > 0
                            ? (_songPosition.inMilliseconds / _songDuration.inMilliseconds).clamp(0.0, 1.0)
                            : 0.0),
                    min: 0, max: 1,
                    onChangeStart: (v) => setState(() { _isDragging = true; _dragPosition = v; }),
                    onChanged: (v) => setState(() => _dragPosition = v),
                    onChangeEnd: (v) {
                      setState(() => _isDragging = false);
                      socket.emit('command_seek',
                          {'position_ms': (v * _songDuration.inMilliseconds).round()});
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(_fmtDuration(_isDragging
                            ? Duration(milliseconds: (_dragPosition * _songDuration.inMilliseconds).round())
                            : _songPosition),
                        style: const TextStyle(color: Colors.white24, fontSize: 11)),
                    Text(_fmtDuration(_songDuration),
                        style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ]),
                ),
              ],
              // Contrôles de décalage des paroles
              if (_lyrics.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _offsetButton("-1s", -1000),
                    _offsetButton("-0.2s", -200),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _lyricsOffsetMs == 0
                            ? "Paroles ±0"
                            : "Paroles ${_lyricsOffsetMs > 0 ? '+' : ''}${(_lyricsOffsetMs / 1000).toStringAsFixed(1)}s",
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    _offsetButton("+0.2s", 200),
                    _offsetButton("+1s", 1000),
                  ]),
                ),
            ]),
          ),

        // --- Barre statut ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: const Color(0xFF16213E),
          child: Row(children: [
            GestureDetector(
              onTap: _toggleMic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 56, width: 56,
                decoration: BoxDecoration(
                  color: isMicOn ? const Color(0xFFE94560) : Colors.grey[800],
                  shape: BoxShape.circle,
                  boxShadow: isMicOn
                      ? [BoxShadow(color: const Color(0xFFE94560).withOpacity(0.6), blurRadius: 15)]
                      : [],
                ),
                child: Icon(isMicOn ? Icons.mic : Icons.mic_off, size: 24, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("EN COURS :", style: TextStyle(color: Colors.grey, fontSize: 11)),
              Text(currentSong != null ? currentSong!['title'] : "Rien ne joue",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            if (currentSong != null) ...[
              IconButton(icon: const Icon(Icons.stop, size: 26, color: Colors.redAccent),
                  onPressed: _stopSong, tooltip: "Arrêter"),
              IconButton(
                  icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause,
                      size: 28, color: _isPaused ? Colors.greenAccent : Colors.white70),
                  onPressed: _togglePause),
              IconButton(icon: const Icon(Icons.skip_next, size: 28, color: Colors.white),
                  onPressed: _playNext),
            ],
            IconButton(
              icon: Icon(Icons.music_note, size: 22,
                  color: _showVolumeBar ? Colors.pinkAccent : Colors.white54),
              onPressed: () => setState(() => _showVolumeBar = !_showVolumeBar),
            ),
          ]),
        ),

        // --- Slider volume musique ---
        if (_showVolumeBar)
          Container(
            color: const Color(0xFF0D0D1A),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Icons.volume_down, color: Colors.white38, size: 18),
              Expanded(child: Slider(
                value: _musicVolume, min: 0, max: 1,
                activeColor: const Color(0xFFE94560), inactiveColor: Colors.white24,
                onChanged: (v) { setState(() => _musicVolume = v); _localPlayer.setVolume(v); },
              )),
              const Icon(Icons.volume_up, color: Colors.white38, size: 18),
              SizedBox(width: 36, child: Text("${(_musicVolume * 100).round()}%",
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                  textAlign: TextAlign.right)),
            ]),
          ),

        // --- File d'attente ---
        if (queue.isNotEmpty)
          Container(
            color: Colors.black12, height: 110,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(
                padding: EdgeInsets.only(left: 15, top: 5),
                child: Text("FILE D'ATTENTE (Restez appuyé) :",
                    style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  proxyDecorator: (child, _, anim) => Material(color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.6),
                                blurRadius: 15, spreadRadius: 2)]),
                        child: child,
                      )),
                  onReorder: (oldI, newI) {
                    setState(() {
                      if (oldI < newI) newI -= 1;
                      final item = queue.removeAt(oldI);
                      queue.insert(newI, item);
                    });
                    socket.emit('reorder_queue', {'oldIndex': oldI, 'newIndex': newI});
                  },
                  itemCount: queue.length,
                  itemBuilder: (ctx, i) {
                    final song = queue[i];
                    return Container(
                      key: ValueKey(song['queue_id']),
                      width: 150, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Stack(children: [
                        Container(
                          width: double.infinity, height: double.infinity, padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.queue_music, color: Colors.blue, size: 20),
                            const SizedBox(height: 5),
                            Text(song['title'], maxLines: 1, overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center),
                          ]),
                        ),
                        Positioned(top: 0, right: 0,
                          child: GestureDetector(
                            onTap: () => _removeFromQueue(i),
                            child: Container(padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF1A1A2E), width: 2)),
                                child: const Icon(Icons.close, size: 14, color: Colors.white)),
                          )),
                      ]),
                    );
                  },
                ),
              ),
            ]),
          ),

        const Divider(height: 1, color: Colors.white24),

        // --- Téléchargements actifs ---
        if (activeDownloads.isNotEmpty)
          ...activeDownloads.map((dl) => ListTile(
            tileColor: Colors.purple.withOpacity(0.2),
            leading: const CircularProgressIndicator(color: Colors.purpleAccent),
            title: Text("Création : ${dl['title']}", maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text("Extraction...", style: TextStyle(color: Colors.grey, fontSize: 12)),
            trailing: IconButton(icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () => _cancelDownload(dl['id'])),
          )).toList(),

        // --- Filtres ---
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
          child: Row(children: [
            Expanded(child: TextField(controller: _localTitleController,
                decoration: const InputDecoration(labelText: "Titre",
                    prefixIcon: Icon(Icons.music_note, size: 20),
                    border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _localArtistController,
                decoration: const InputDecoration(labelText: "Artiste",
                    prefixIcon: Icon(Icons.person, size: 20),
                    border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _showFavoritesOnly = !_showFavoritesOnly),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _showFavoritesOnly ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _showFavoritesOnly ? Colors.amber : Colors.white24),
                ),
                child: Icon(_showFavoritesOnly ? Icons.star : Icons.star_border,
                    color: _showFavoritesOnly ? Colors.amber : Colors.white38, size: 22),
              ),
            ),
          ]),
        ),

        // --- Liste des chansons ---
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _fetchSongs, color: Colors.pink,
                  child: filteredSongs.isEmpty
                      ? Center(child: Text(
                          _showFavoritesOnly ? "Aucun favori." : "Aucune chanson.",
                          style: const TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredSongs.length,
                          itemBuilder: (ctx, i) {
                            final song = filteredSongs[i];
                            final isFav = _favorites.contains(song['id']);
                            return ListTile(
                              leading: const Icon(Icons.music_note, color: Colors.pink),
                              title: Text(song['title']),
                              subtitle: Text(song['has_lyrics'] ? "Paroles OK" : "Instru seul"),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                    icon: Icon(isFav ? Icons.star : Icons.star_border, size: 24,
                                        color: isFav ? Colors.amber : Colors.white38),
                                    onPressed: () => _toggleFavorite(song['id'])),
                                IconButton(
                                    icon: const Icon(Icons.add_circle, size: 28, color: Colors.greenAccent),
                                    onPressed: () => _handleSongTap(song)),
                                IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 24, color: Colors.redAccent),
                                    onPressed: () => _confirmDeleteSong(song)),
                              ]),
                            );
                          },
                        ),
                ),
        ),
      ]),
    );
  }

  Widget _offsetButton(String label, int deltaMs) => TextButton(
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    onPressed: () => _adjustOffset(deltaMs),
    child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
  );
}
