import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/config.dart';
import 'package:app/screens/role_selection_screen.dart';

class ServerSetupScreen extends StatefulWidget {
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

    if (!ip.startsWith("http://") && !ip.startsWith("https://")) ip = "http://$ip";
    if (!ip.contains(":5000")) ip = "$ip:5000";

    try {
      final response = await http.get(Uri.parse(ip)).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('server_ip', _ipController.text.trim());
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
          decoration: BoxDecoration(
            color: const Color(0xFF16213E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blueAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.router, size: 60, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text("Serveur Karaorkey", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                "Entrez l'adresse IP locale de votre ordinateur (ex: 192.168.1.45)",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ipController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Adresse IP",
                  hintText: "192.168.1.XX",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
                onSubmitted: (_) => _connect(),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 15),
                Text(_errorMessage,
                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE94560),
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      ),
                      onPressed: _connect,
                      child: const Text("Se Connecter",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
