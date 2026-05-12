import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:just_audio/just_audio.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import 'package:app/config.dart';
import 'package:app/models/lyric_line.dart';
import 'package:app/widgets/youtube_search_dialog.dart';

class MicRemoteScreen extends StatefulWidget {
  final String roomName;
  final String password;
  const MicRemoteScreen({super.key, required this.roomName, required this.password});
  @override
  State<MicRemoteScreen> createState() => _MicRemoteScreenState();
}

class _MicRemoteScreenState extends State<MicRemoteScreen> {
  late IO.Socket socket;

  // --- Audio local (monitor chanteur) ---
  late AudioPlayer _localPlayer;
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _micOutput = PlayerStream();
  bool isMicOn = false;
  StreamSubscription? _micSubscription;

  // --- Paroles sync ---
  List<LyricLine> _lyrics = [];
  int _lyricIndex = -1;

  // --- État de la salle ---
  bool isReconnecting = false;
  List<dynamic> allSongs = [];
  List<dynamic> activeDownloads = [];
  bool isLoading = true;
  Map<String, dynamic>? currentSong;
  List<Map<String, dynamic>> queue = [];

  // --- Filtres bibliothèque ---
  final TextEditingController _localTitleController = TextEditingController();
  final TextEditingController _localArtistController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _localPlayer = AudioPlayer();
    _localPlayer.positionStream.listen((pos) {
      if (mounted) _syncLyrics(pos);
    });
    _localPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() { _lyrics = []; _lyricIndex = -1; });
      }
    });
    _initSocket();
    _initAudio();
    _fetchSongs();
    _localTitleController.addListener(() => setState(() {}));
    _localArtistController.addListener(() => setState(() {}));
  }

  // ==========================================
  // SOCKET
  // ==========================================

  void _joinRoom() {
    socket.emit('join_karaoke_room', {
      'room': widget.roomName,
      'role': 'dj',
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("La salle a été fermée !"), backgroundColor: Colors.orange));
        Navigator.pop(context);
      }
    });

    // Le DJ reçoit start_song comme la TV → démarre le monitor local
    socket.on('start_song', (data) {
      _startLocalPlayback(data['id'], data['title']);
    });

    socket.on('stop_song', (_) {
      _localPlayer.stop();
      if (mounted) setState(() { _lyrics = []; _lyricIndex = -1; });
    });

    socket.on('sync_state', (data) {
      if (mounted) setState(() {
        currentSong = data['current_song'];
        queue = List<Map<String, dynamic>>.from(data['queue']);
      });
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

  Future<void> _startLocalPlayback(String songId, String title) async {
    if (mounted) setState(() { _lyrics = []; _lyricIndex = -1; });
    await _loadLyrics(songId);
    try {
      await _localPlayer.stop();
      await _localPlayer.setUrl('$baseUrl/api/play/$songId/audio');
      await _localPlayer.setVolume(1.0);
      _localPlayer.play();
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
                timestamp: Duration(
                  minutes: int.parse(m.group(1)!),
                  seconds: int.parse(m.group(2)!),
                  milliseconds: ms,
                ),
                text: text,
              ));
            }
          }
        }
        if (mounted) setState(() => _lyrics = parsed);
      }
    } catch (_) {}
  }

  void _syncLyrics(Duration position) {
    if (_lyrics.isEmpty) return;
    for (int i = 0; i < _lyrics.length; i++) {
      final isLast = i == _lyrics.length - 1;
      final isCurrent = isLast
          ? position >= _lyrics[i].timestamp
          : position >= _lyrics[i].timestamp && position < _lyrics[i + 1].timestamp;
      if (isCurrent) {
        if (_lyricIndex != i) setState(() => _lyricIndex = i);
        break;
      }
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
      _micSubscription?.cancel();
      await _recorder.stop();
      setState(() => isMicOn = false);
    } else {
      if (await Permission.microphone.request().isGranted) {
        await _micOutput.start();
        await _recorder.start();
        _micSubscription = _recorder.audioStream.listen((data) => _micOutput.writeChunk(data));
        setState(() => isMicOn = true);
      }
    }
  }

  // ==========================================
  // CONTRÔLES DJ
  // ==========================================

  Future<void> _fetchSongs() async {
    if (!mounted) return;
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/songs'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && mounted) {
        setState(() { allSongs = json.decode(response.body); isLoading = false; });
      }
    } catch (e) { if (mounted) setState(() => isLoading = false); }
  }

  void _handleSongTap(dynamic song) {
    if (currentSong == null) {
      socket.emit('command_play', song);
    } else {
      socket.emit('add_to_queue', song);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("🎵 Ajouté : ${song['title']}")));
    }
  }

  void _playNext() => socket.emit('play_next');
  void _removeFromQueue(int index) => socket.emit('remove_from_queue', {'index': index});

  Future<void> _triggerDownload(String url, String title) async {
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
      content: Text("Supprimer définitivement « ${song['title']} » de la bibliothèque ?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            Navigator.pop(context);
            try {
              final res = await http.post(
                Uri.parse('$baseUrl/api/delete_song'),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"song_id": song['id']}),
              );
              if (res.statusCode == 200) {
                _fetchSongs();
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
    _recorder.stop();
    _micOutput.stop();
    _localTitleController.dispose();
    _localArtistController.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  List<dynamic> get filteredSongs {
    final searchTitle = _localTitleController.text.toLowerCase();
    final searchArtist = _localArtistController.text.toLowerCase();
    return allSongs.where((song) {
      final songTitle = song['title'].toString().toLowerCase();
      final parts = songTitle.split(' - ');
      final titlePart = parts.length > 1 ? parts.sublist(1).join(' - ') : songTitle;
      final artistPart = parts[0];
      return titlePart.contains(searchTitle) && artistPart.contains(searchArtist);
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
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                SizedBox(width: 6),
                Text("Reconnexion...", style: TextStyle(fontSize: 12, color: Colors.orange)),
              ]),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pink,
        onPressed: () => showDialog(context: context,
            builder: (_) => YoutubeSearchDialog(onDownload: _triggerDownload)),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [

          // --- Monitor paroles (visible uniquement quand une chanson joue) ---
          if (currentSong != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF0D0D1A),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    currentLine.isEmpty ? "♪" : currentLine,
                    key: ValueKey<String>('dj_current_$currentLine'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: currentLine.isEmpty ? Colors.white12 : const Color(0xFFE94560),
                    ),
                  ),
                ),
                if (nextLine.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      nextLine,
                      key: ValueKey<String>('dj_next_$nextLine'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, color: Colors.white38),
                    ),
                  ),
                ],
              ]),
            ),

          // --- Barre statut lecture + micro ---
          Container(
            padding: const EdgeInsets.all(15),
            color: const Color(0xFF16213E),
            child: Row(children: [
              GestureDetector(
                onTap: _toggleMic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 70, width: 70,
                  decoration: BoxDecoration(
                    color: isMicOn ? const Color(0xFFE94560) : Colors.grey[800],
                    shape: BoxShape.circle,
                    boxShadow: isMicOn
                        ? [BoxShadow(color: const Color(0xFFE94560).withOpacity(0.6), blurRadius: 15)]
                        : [],
                  ),
                  child: Icon(isMicOn ? Icons.mic : Icons.mic_off, size: 30, color: Colors.white),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("EN COURS :", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Text(
                    currentSong != null ? currentSong!['title'] : "Rien ne joue",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              )),
              if (currentSong != null)
                IconButton(
                    icon: const Icon(Icons.skip_next, size: 35, color: Colors.white),
                    onPressed: _playNext),
            ]),
          ),

          // --- File d'attente ---
          if (queue.isNotEmpty)
            Container(
              color: Colors.black12, height: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 15, top: 5),
                    child: Text("FILE D'ATTENTE (Restez appuyé) :",
                        style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      proxyDecorator: (child, index, animation) => Material(
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(
                                color: Colors.pinkAccent.withOpacity(0.6),
                                blurRadius: 15, spreadRadius: 2)],
                          ),
                          child: child,
                        ),
                      ),
                      onReorder: (oldIndex, newIndex) {
                        setState(() {
                          if (oldIndex < newIndex) newIndex -= 1;
                          final item = queue.removeAt(oldIndex);
                          queue.insert(newIndex, item);
                        });
                        socket.emit('reorder_queue', {'oldIndex': oldIndex, 'newIndex': newIndex});
                      },
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final song = queue[index];
                        return Container(
                          key: ValueKey(song['queue_id']),
                          width: 150,
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Stack(children: [
                            Container(
                              width: double.infinity, height: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Icon(Icons.queue_music, color: Colors.blue, size: 20),
                                const SizedBox(height: 5),
                                Text(song['title'], maxLines: 1, overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center),
                              ]),
                            ),
                            Positioned(
                              top: 0, right: 0,
                              child: GestureDetector(
                                onTap: () => _removeFromQueue(index),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent, shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFF1A1A2E), width: 2),
                                  ),
                                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1, color: Colors.white24),

          // --- Téléchargements actifs ---
          if (activeDownloads.isNotEmpty)
            ...activeDownloads.map((dl) => ListTile(
              tileColor: Colors.purple.withOpacity(0.2),
              leading: const CircularProgressIndicator(color: Colors.purpleAccent),
              title: Text("Création : ${dl['title']}", maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text("Extraction...", style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.close, color: Colors.redAccent),
                onPressed: () => _cancelDownload(dl['id']),
              ),
            )).toList(),

          // --- Filtres de recherche ---
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(children: [
              Expanded(child: TextField(
                controller: _localTitleController,
                decoration: const InputDecoration(
                  labelText: "Titre",
                  prefixIcon: Icon(Icons.music_note, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(10),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: TextField(
                controller: _localArtistController,
                decoration: const InputDecoration(
                  labelText: "Artiste",
                  prefixIcon: Icon(Icons.person, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(10),
                ),
              )),
            ]),
          ),

          // --- Liste des chansons ---
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchSongs,
                    color: Colors.pink,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filteredSongs.length,
                      itemBuilder: (context, index) {
                        final song = filteredSongs[index];
                        return ListTile(
                          leading: const Icon(Icons.music_note, color: Colors.pink),
                          title: Text(song['title']),
                          subtitle: Text(song['has_lyrics'] ? "Paroles OK" : "Instru seul"),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: const Icon(Icons.add_circle, size: 30, color: Colors.greenAccent),
                              onPressed: () => _handleSongTap(song),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 26, color: Colors.redAccent),
                              onPressed: () => _confirmDeleteSong(song),
                            ),
                          ]),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
