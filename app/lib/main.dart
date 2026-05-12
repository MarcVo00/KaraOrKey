import 'package:flutter/material.dart';
import 'package:app/screens/server_setup_screen.dart';

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
