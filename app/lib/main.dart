import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:just_audio/just_audio.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

String baseUrl = "";

void main() {
  runApp(const KaraokeApp());
}

class KaraokeApp extends StatelessWidget {
  const KaraokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Karaorkey',
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFFE94560),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF16213E)),
      ),
      home: const ServerSetupScreen(), 
      debugShowCheckedModeBanner: false,
    );
  }
}

class ServerSetupScreen extends StatefulWidget{
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}
class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('server_ip');
    if (savedIp != null && savedIp.isNotEmpty) {
      _ipController.text = savedIp;
    }
  }

  Future<void> _connect() async {
    setState(() { _isLoading = true; _errorMessage = ""; });

    String ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() { _isLoading = false; _errorMessage = "Veuillez entrer une adresse IP"; });
      return;
    }

    // Formatage automatique pour aider l'utilisateur
    if (!ip.startsWith("http://") && !ip.startsWith("https://")) ip = "http://$ip";
    if (!ip.contains(":5000")) ip = "$ip:5000";

    try {
      // Test de connexion rapide avec un "ping" sur le serveur
      final response = await http.get(Uri.parse(ip)).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        
        // C'est un succès ! On sauvegarde l'IP pour la prochaine fois
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server_ip', _ipController.text.trim());

        // On met à jour la variable globale pour tout le reste du code
        baseUrl = ip;

        if (mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()));
        }
      } else {
         setState(() => _errorMessage = "Le serveur a répondu avec une erreur.");
      }
    } catch (e) {
      setState(() => _errorMessage = "Impossible de joindre le serveur.\nVérifiez l'IP et que vous êtes sur le même Wi-Fi.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFF16213E), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueAccent, width: 2)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.router, size: 60, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text("Serveur Karaorkey", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Entrez l'adresse IP locale de votre ordinateur (ex: 192.168.1.45)", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              TextField(
                controller: _ipController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Adresse IP", hintText: "192.168.1.XX", border: OutlineInputBorder(), prefixIcon: Icon(Icons.wifi)),
                onSubmitted: (_) => _connect(),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 15),
                Text(_errorMessage, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE94560), padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
                      onPressed: _connect,
                      child: const Text("Se Connecter", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 1. SÉLECTION DU RÔLE (AVEC COMPATIBILITÉ TV)
// ==========================================
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("KARAORKEY", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFFE94560), letterSpacing: 5)),
            const SizedBox(height: 10),
            const Text("Choisissez votre appareil", style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 60),
            
            _RoleButton(
              icon: Icons.mic,
              label: "PANNEAU DJ & MICROPHONE\n(Téléphone / Tablette)",
              color: const Color(0xFFE94560),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomSelectionScreen(role: 'dj'))),
            ),
            const SizedBox(height: 30),
            _RoleButton(
              icon: Icons.tv,
              label: "ÉCRAN TV\n(Affichage des paroles)",
              color: Colors.blueAccent,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomSelectionScreen(role: 'tv'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _RoleButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        focusColor: color.withOpacity(0.4), // Pour la télécommande Android TV
        hoverColor: color.withOpacity(0.4),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2), 
            borderRadius: BorderRadius.circular(20), 
            border: Border.all(color: color, width: 2)
          ),
          child: Column(
            children: [
              Icon(icon, size: 60, color: color),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. SÉLECTION DE LA SALLE (DYNAMIQUE)
// ==========================================
class RoomSelectionScreen extends StatefulWidget {
  final String role; // 'tv' ou 'dj'
  const RoomSelectionScreen({super.key, required this.role});

  @override
  State<RoomSelectionScreen> createState() => _RoomSelectionScreenState();
}

class _RoomSelectionScreenState extends State<RoomSelectionScreen> {
  List<dynamic> rooms = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  Future<void> _fetchRooms() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/rooms'));
      if (response.statusCode == 200 && mounted) {
        setState(() { rooms = json.decode(response.body); isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showCreateRoomDialog() {
    final TextEditingController nameCtrl = TextEditingController();
    final TextEditingController pwdCtrl = TextEditingController();

    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text("Créer une Salle 🎵"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Nom de la salle")),
          const SizedBox(height: 10),
          TextField(controller: pwdCtrl, decoration: const InputDecoration(labelText: "Mot de passe (Optionnel)"), obscureText: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          onPressed: () async {
            if (nameCtrl.text.isEmpty) return;
            Navigator.pop(context);
            setState(() => isLoading = true);
            try {
              final res = await http.post(
                Uri.parse('$baseUrl/api/create_room'),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({"name": nameCtrl.text, "password": pwdCtrl.text}),
              );
              final data = jsonDecode(res.body);
              if (res.statusCode != 200 && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['error']), backgroundColor: Colors.red));
              }
              _fetchRooms();
            } catch (e) { _fetchRooms(); }
          },
          child: const Text("Créer"),
        )
      ],
    ));
  }

  void _handleDelete(Map room) {
    if (room['is_private']) {
      _askPassword(room['name'], "Mot de passe pour supprimer", (pwd) => _deleteRoom(room['name'], pwd));
    } else {
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text("Supprimer la salle ?"),
        content: Text("Êtes-vous sûr de vouloir supprimer '${room['name']}' ? Tout le monde sera expulsé."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () { Navigator.pop(context); _deleteRoom(room['name'], ""); }, child: const Text("Supprimer")),
        ],
      ));
    }
  }

  Future<void> _deleteRoom(String name, String pwd) async {
    setState(() => isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/delete_room'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"name": name, "password": pwd}),
      );
      if (res.statusCode != 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(jsonDecode(res.body)['error']), backgroundColor: Colors.red));
      }
      _fetchRooms();
    } catch (e) { _fetchRooms(); }
  }

  void _handleJoin(Map room) {
    if (room['is_private']) {
      _askPassword(room['name'], "Mot de passe requis", (pwd) => _enterRoom(room['name'], pwd));
    } else {
      _enterRoom(room['name'], "");
    }
  }

  void _askPassword(String roomName, String title, Function(String) onSubmit) {
    final TextEditingController pwdCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: pwdCtrl, decoration: const InputDecoration(labelText: "Mot de passe"), obscureText: true, autofocus: true, onSubmitted: (val) { Navigator.pop(context); onSubmit(val); }),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(onPressed: () { Navigator.pop(context); onSubmit(pwdCtrl.text); }, child: const Text("Valider")),
      ],
    ));
  }

  void _enterRoom(String roomName, String password) {
    if (widget.role == 'dj') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => MicRemoteScreen(roomName: roomName, password: password))).then((_) => _fetchRooms());
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => TVPlayerScreen(roomName: roomName, password: password))).then((_) => _fetchRooms());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Où allez-vous ? (${widget.role == 'dj' ? 'DJ' : 'Écran'})"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchRooms)],
      ),
      floatingActionButton: widget.role == 'dj' 
          ? FloatingActionButton(backgroundColor: Colors.pink, onPressed: _showCreateRoomDialog, child: const Icon(Icons.add)) 
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                bool isFullForMe = widget.role == 'tv' && room['has_tv'] == true;

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  leading: Icon(
                    isFullForMe ? Icons.lock : Icons.meeting_room,
                    color: isFullForMe ? Colors.red : Colors.greenAccent,
                    size: 40,
                  ),
                  title: Row(
                    children: [
                      Text(room['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      if (room['is_private']) const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.lock, size: 16, color: Colors.orange)),
                    ],
                  ),
                  subtitle: Text("TV: ${room['has_tv'] ? 'Occupée 🔴' : 'Libre 🟢'}  |  DJs: ${room['dj_count']}"),
                  enabled: !isFullForMe,
                  onTap: () => _handleJoin(room),
                  trailing: widget.role == 'dj' ? IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _handleDelete(room)) : null,
                );
              },
            ),
    );
  }
}

// ==========================================
// 3. MODE MICRO & DJ
// ==========================================
class MicRemoteScreen extends StatefulWidget {
  final String roomName;
  final String password;
  const MicRemoteScreen({super.key, required this.roomName, required this.password});
  @override
  State<MicRemoteScreen> createState() => _MicRemoteScreenState();
}

class _MicRemoteScreenState extends State<MicRemoteScreen> {
  late IO.Socket socket;
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _micOutput = PlayerStream();
  bool isMicOn = false;
  StreamSubscription? _micSubscription;
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
    _initSocket();
    _initAudio();
    _fetchSongs();
    _localTitleController.addListener(() => setState(() {}));
    _localArtistController.addListener(() => setState(() {}));
  }

  void _initSocket() {
    socket = IO.io(baseUrl, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
    socket.connect();

    socket.onConnect((_) {
      socket.emit('join_karaoke_room', {'room': widget.roomName, 'role': 'dj', 'password': widget.password});
    });

    socket.on('join_error', (data) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.red));
        Navigator.pop(context);
      }
    });

    socket.on('room_deleted', (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("La salle a été fermée !"), backgroundColor: Colors.orange));
        Navigator.pop(context);
      }
    });

    socket.on('sync_state', (data) {
      if (mounted) setState(() { currentSong = data['current_song']; queue = List<Map<String, dynamic>>.from(data['queue']); });
    });
    socket.on('download_progress', (data) { if (mounted) setState(() { if (data is List) activeDownloads = data; }); });
    socket.on('download_error', (data) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.red, duration: const Duration(seconds: 5))); });
    socket.on('library_updated', (_) { _fetchSongs(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎉 Karaoké prêt !"))); });
  }

  Future<void> _initAudio() async { try { await _recorder.initialize(); await _micOutput.initialize(); } catch (e) {} }
  Future<void> _fetchSongs() async {
    if (!mounted) return;
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/songs')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && mounted) setState(() { allSongs = json.decode(response.body); isLoading = false; });
    } catch (e) { if (mounted) setState(() { isLoading = false; }); }
  }

  Future<void> _toggleMic() async {
    if (isMicOn) {
      _micSubscription?.cancel(); await _recorder.stop(); setState(() => isMicOn = false);
    } else {
      if (await Permission.microphone.request().isGranted) {
        await _micOutput.start(); await _recorder.start();
        _micSubscription = _recorder.audioStream.listen((data) { _micOutput.writeChunk(data); });
        setState(() => isMicOn = true);
      }
    }
  }

  void _handleSongTap(dynamic song) {
    if (currentSong == null) socket.emit('command_play', song); 
    else { socket.emit('add_to_queue', song); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🎵 Ajouté : ${song['title']}"))); }
  }

  void _playNext() => socket.emit('play_next'); 
  void _removeFromQueue(int index) => socket.emit('remove_from_queue', {'index': index});
  Future<void> _triggerDownload(String url, String title) async { try { await http.post(Uri.parse('$baseUrl/api/add_youtube'), headers: {"Content-Type": "application/json"}, body: jsonEncode({"url": url, "title": title})); } catch (e) {} }
  Future<void> _cancelDownload(String taskId) async { try { await http.post(Uri.parse('$baseUrl/api/cancel'), headers: {"Content-Type": "application/json"}, body: jsonEncode({"task_id": taskId})); } catch (e) {} }

  @override
  void dispose() {
    socket.dispose(); _micSubscription?.cancel(); _recorder.stop(); _micOutput.stop(); _localTitleController.dispose(); _localArtistController.dispose(); WakelockPlus.disable();
    super.dispose();
  }

  List<dynamic> get filteredSongs {
    final searchTitle = _localTitleController.text.toLowerCase();
    final searchArtist = _localArtistController.text.toLowerCase();
    return allSongs.where((song) { final songTitle = song['title'].toString().toLowerCase(); return songTitle.contains(searchTitle) && songTitle.contains(searchArtist); }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("DJ - ${widget.roomName}")),
      floatingActionButton: FloatingActionButton(backgroundColor: Colors.pink, onPressed: () { showDialog(context: context, builder: (_) => YoutubeSearchDialog(onDownload: _triggerDownload)); }, child: const Icon(Icons.add)),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(15), color: const Color(0xFF16213E),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleMic,
                  child: AnimatedContainer(duration: const Duration(milliseconds: 300), height: 70, width: 70, decoration: BoxDecoration(color: isMicOn ? const Color(0xFFE94560) : Colors.grey[800], shape: BoxShape.circle, boxShadow: isMicOn ? [BoxShadow(color: const Color(0xFFE94560).withOpacity(0.6), blurRadius: 15)] : []), child: Icon(isMicOn ? Icons.mic : Icons.mic_off, size: 30, color: Colors.white)),
                ),
                const SizedBox(width: 15),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("EN COURS :", style: TextStyle(color: Colors.grey, fontSize: 12)), Text(currentSong != null ? currentSong!['title'] : "Rien ne joue", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis)])),
                if (currentSong != null) IconButton(icon: const Icon(Icons.skip_next, size: 35, color: Colors.white), onPressed: _playNext)
              ],
            ),
          ),
          if (queue.isNotEmpty)
            Container(
              color: Colors.black12, height: 110,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(left: 15, top: 5), child: Text("FILE D'ATTENTE (Restez appuyé) :", style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(
                    child: ReorderableListView.builder(
                      scrollDirection: Axis.horizontal,
                      proxyDecorator: (Widget child, int index, Animation<double> animation) { return Material(color: Colors.transparent, child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.6), blurRadius: 15, spreadRadius: 2)]), child: child)); },
                      onReorder: (oldIndex, newIndex) { setState(() { if (oldIndex < newIndex) newIndex -= 1; final item = queue.removeAt(oldIndex); queue.insert(newIndex, item); }); socket.emit('reorder_queue', {'oldIndex': oldIndex, 'newIndex': newIndex}); },
                      itemCount: queue.length,
                      itemBuilder: (context, index) {
                        final song = queue[index];
                        return Container(
                          key: ValueKey(song['queue_id']), width: 150, margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Stack(
                            children: [
                              Container(width: double.infinity, height: double.infinity, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.queue_music, color: Colors.blue, size: 20), const SizedBox(height: 5), Text(song['title'], maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)])),
                              Positioned(top: 0, right: 0, child: GestureDetector(onTap: () => _removeFromQueue(index), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1A1A2E), width: 2)), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1, color: Colors.white24),
          if (activeDownloads.isNotEmpty)
            ...activeDownloads.map((dl) => ListTile(tileColor: Colors.purple.withOpacity(0.2), leading: const CircularProgressIndicator(color: Colors.purpleAccent), title: Text("Création : ${dl['title']}", maxLines: 1, overflow: TextOverflow.ellipsis), subtitle: const Text("Extraction...", style: TextStyle(color: Colors.grey, fontSize: 12)), trailing: IconButton(icon: const Icon(Icons.close, color: Colors.redAccent), onPressed: () => _cancelDownload(dl['id'])))).toList(),
          Padding(padding: const EdgeInsets.all(10.0), child: Row(children: [Expanded(child: TextField(controller: _localTitleController, decoration: const InputDecoration(labelText: "Titre", prefixIcon: Icon(Icons.music_note, size: 20), border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10)))), const SizedBox(width: 10), Expanded(child: TextField(controller: _localArtistController, decoration: const InputDecoration(labelText: "Artiste", prefixIcon: Icon(Icons.person, size: 20), border: OutlineInputBorder(), contentPadding: EdgeInsets.all(10))))])),
          Expanded(child: isLoading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: _fetchSongs, color: Colors.pink, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(), itemCount: filteredSongs.length, itemBuilder: (context, index) { final song = filteredSongs[index]; return ListTile(leading: const Icon(Icons.music_note, color: Colors.pink), title: Text(song['title']), subtitle: Text(song['has_lyrics'] ? "Paroles OK" : "Instru seul"), trailing: IconButton(icon: const Icon(Icons.add_circle, size: 30, color: Colors.greenAccent), onPressed: () => _handleSongTap(song))); }))),
        ],
      ),
    );
  }
}

// ==========================================
// 4. MODE TV
// ==========================================
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

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _tvPlayer = AudioPlayer();
    _initSocket();
    _tvPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) { socket.emit('play_next'); if (mounted) { setState(() { lyrics = []; currentLyricIndex = -1; currentTitle = "Prêt à chanter !"; }); } }
    });
  }

  void _initSocket() {
    socket = IO.io(baseUrl, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
    socket.connect();
    
    socket.onConnect((_) {
      socket.emit('join_karaoke_room', {'room': widget.roomName, 'role': 'tv', 'password': widget.password});
    });

    socket.on('join_error', (data) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.red)); Navigator.pop(context); }
    });

    socket.on('room_deleted', (_) {
      if (mounted) { Navigator.pop(context); }
    });

    socket.on('start_song', (data) { _startVisuals(data['id'], data['title']); });
    socket.on('stop_song', (_) { if (mounted) { setState(() { lyrics = []; currentLyricIndex = -1; currentTitle = "Prêt à chanter !"; }); _tvPlayer.stop(); } });
  }

  Future<void> _startVisuals(String songId, String title) async {
    setState(() { currentTitle = title; lyrics = []; currentLyricIndex = -1; });
    await _loadLyrics(songId);
    try { await _tvPlayer.stop(); await _tvPlayer.setUrl('$baseUrl/api/play/$songId/audio'); await _tvPlayer.setVolume(1.0); _tvPlayer.play(); _tvPlayer.positionStream.listen((pos) => _syncLyrics(pos)); } catch (e) {}
  }

  Future<void> _loadLyrics(String songId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/play/$songId/lyrics'));
      if (response.statusCode == 200) {
        final lines = utf8.decode(response.bodyBytes).split('\n');
        final parsedLyrics = <LyricLine>[];
        final regExp = RegExp(r"^\[(\d{2}):(\d{2})\.(\d{2})\](.*)");
        for (var line in lines) { final match = regExp.firstMatch(line); if (match != null) { final text = match.group(4)!.trim(); if (text.isNotEmpty) { parsedLyrics.add(LyricLine(timestamp: Duration(minutes: int.parse(match.group(1)!), seconds: int.parse(match.group(2)!), milliseconds: int.parse(match.group(3)!)*10), text: text)); } } }
        if (mounted) setState(() { lyrics = parsedLyrics; });
      }
    } catch (e) {}
  }

  void _syncLyrics(Duration position) {
    if (lyrics.isEmpty) return;
    for (int i = 0; i < lyrics.length; i++) {
      bool isLastLine = (i == lyrics.length - 1); bool isCurrent = isLastLine ? (position >= lyrics[i].timestamp) : (position >= lyrics[i].timestamp && position < lyrics[i + 1].timestamp);
      if (isCurrent) { if (currentLyricIndex != i) setState(() { currentLyricIndex = i; }); break; }
    }
  }

  @override
  void dispose() { socket.dispose(); _tvPlayer.dispose(); WakelockPlus.disable(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    String currentLine = ""; 
    String nextLine = "";
    
    if (lyrics.isNotEmpty && currentLyricIndex >= 0) { 
      currentLine = lyrics[currentLyricIndex].text; 
      if (currentLyricIndex + 1 < lyrics.length) {
        nextLine = lyrics[currentLyricIndex + 1].text; 
      }
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 50.0, bottom: 20.0), 
            child: Text(currentTitle, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueAccent))
          ),
          Expanded(
            child: lyrics.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, 
                    children: [
                      const Icon(Icons.music_note, size: 80, color: Colors.white24), 
                      const SizedBox(height: 20), 
                      Text("En attente du DJ...", style: TextStyle(color: Colors.grey[600], fontSize: 24))
                    ]
                  )
                ) 
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0), 
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center, 
                    children: [
                      // --- LIGNE ACTUELLE ANIMÉE ---
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        // Le 'ValueKey' est crucial : il dit à Flutter que le texte a changé et qu'il faut déclencher l'animation !
                        child: Text(
                          currentLine, 
                          key: ValueKey<String>('current_$currentLine'),
                          textAlign: TextAlign.center, 
                          style: const TextStyle(
                            fontSize: 48, 
                            fontWeight: FontWeight.bold, 
                            color: Color(0xFFE94560), 
                            shadows: [Shadow(blurRadius: 15, color: Color(0xFFE94560))]
                          )
                        )
                      ),
                      
                      const SizedBox(height: 50), 
                      
                      // --- LIGNE SUIVANTE ANIMÉE ---
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: Text(
                          nextLine, 
                          key: ValueKey<String>('next_$nextLine'),
                          textAlign: TextAlign.center, 
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.normal, color: Colors.white30)
                        )
                      )
                    ]
                  )
                )
          ),
        ],
      ),
    );
  }
}

// ==========================================
// UTILITAIRES
// ==========================================

class LyricLine {
  final Duration timestamp;
  final String text;
  LyricLine({required this.timestamp, required this.text});
}

// ==========================================
// 5. BOITE DE RECHERCHE YOUTUBE
// ==========================================
class YoutubeSearchDialog extends StatefulWidget {
  final Function(String, String) onDownload;
  const YoutubeSearchDialog({super.key, required this.onDownload});
  @override
  State<YoutubeSearchDialog> createState() => _YoutubeSearchDialogState();
}

class _YoutubeSearchDialogState extends State<YoutubeSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> results = [];
  bool isSearching = false;

  Future<void> _searchYoutube() async {
    if (_searchController.text.isEmpty) return;
    setState(() { isSearching = true; });
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/search?q=${Uri.encodeComponent(_searchController.text)}'));
      if (response.statusCode == 200) {
        setState(() { results = json.decode(response.body); });
      }
    } catch (e) {
      print("Erreur: $e");
    }
    setState(() { isSearching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Chercher sur YouTube"),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Artiste - Titre",
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _searchYoutube),
              ),
              onSubmitted: (_) => _searchYoutube(),
            ),
            const SizedBox(height: 20),
            if (isSearching) const CircularProgressIndicator(),
            if (!isSearching && results.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final video = results[index];
                    return ListTile(
                      leading: const Icon(Icons.ondemand_video, color: Colors.red),
                      title: Text(video['title'], maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        icon: const Icon(Icons.download, color: Colors.green),
                        onPressed: () {
                          widget.onDownload(video['url'], video['title']);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Fermer"))],
    );
  }
}