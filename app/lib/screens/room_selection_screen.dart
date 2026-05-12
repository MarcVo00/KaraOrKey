import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:app/config.dart';
import 'package:app/screens/mic_remote_screen.dart';
import 'package:app/screens/tv_player_screen.dart';

class RoomSelectionScreen extends StatefulWidget {
  final String role;
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
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(data['error']), backgroundColor: Colors.red));
              }
              _fetchRooms();
            } catch (e) { _fetchRooms(); }
          },
          child: const Text("Créer"),
        ),
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () { Navigator.pop(context); _deleteRoom(room['name'], ""); },
            child: const Text("Supprimer"),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(jsonDecode(res.body)['error']), backgroundColor: Colors.red));
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
      content: TextField(
        controller: pwdCtrl,
        decoration: const InputDecoration(labelText: "Mot de passe"),
        obscureText: true,
        autofocus: true,
        onSubmitted: (val) { Navigator.pop(context); onSubmit(val); },
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
            onPressed: () { Navigator.pop(context); onSubmit(pwdCtrl.text); },
            child: const Text("Valider")),
      ],
    ));
  }

  void _enterRoom(String roomName, String password) {
    if (widget.role == 'dj') {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => MicRemoteScreen(roomName: roomName, password: password)))
          .then((_) => _fetchRooms());
    } else {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => TVPlayerScreen(roomName: roomName, password: password)))
          .then((_) => _fetchRooms());
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
          ? FloatingActionButton(
              backgroundColor: Colors.pink,
              onPressed: _showCreateRoomDialog,
              child: const Icon(Icons.add))
          : null,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: rooms.length,
              itemBuilder: (context, index) {
                final room = rooms[index];
                final isFullForMe = widget.role == 'tv' && room['has_tv'] == true;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                  leading: Icon(
                    isFullForMe ? Icons.lock : Icons.meeting_room,
                    color: isFullForMe ? Colors.red : Colors.greenAccent,
                    size: 40,
                  ),
                  title: Row(children: [
                    Text(room['name'],
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    if (room['is_private'])
                      const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: Icon(Icons.lock, size: 16, color: Colors.orange)),
                  ]),
                  subtitle: Text(
                      "TV: ${room['has_tv'] ? 'Occupée 🔴' : 'Libre 🟢'}  |  DJs: ${room['dj_count']}"),
                  enabled: !isFullForMe,
                  onTap: () => _handleJoin(room),
                  trailing: widget.role == 'dj'
                      ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _handleDelete(room))
                      : null,
                );
              },
            ),
    );
  }
}
