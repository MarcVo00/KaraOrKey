import 'package:flutter/material.dart';
import 'package:app/screens/room_selection_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("KARAORKEY",
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE94560),
                    letterSpacing: 5)),
            const SizedBox(height: 10),
            const Text("Choisissez votre appareil",
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 60),
            _RoleButton(
              icon: Icons.mic,
              label: "PANNEAU DJ & MICROPHONE\n(Téléphone / Tablette)",
              color: const Color(0xFFE94560),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RoomSelectionScreen(role: 'dj'))),
            ),
            const SizedBox(height: 30),
            _RoleButton(
              icon: Icons.tv,
              label: "ÉCRAN TV\n(Affichage des paroles)",
              color: Colors.blueAccent,
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const RoomSelectionScreen(role: 'tv'))),
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
        focusColor: color.withOpacity(0.4),
        hoverColor: color.withOpacity(0.4),
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color, width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, size: 60, color: color),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
