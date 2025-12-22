import 'dart:ui';
import 'package:flutter/material.dart';
import '../main_screen.dart';

class AlternativePathScreen extends StatelessWidget {
  const AlternativePathScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      body: Stack(
        children: [

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alt_route, size: 80, color: Colors.green),
                const SizedBox(height: 20),
                const Text(
                  'Percorsi Alternativi',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Evita l\'acqua alta con questi percorsi.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _StickyHeader(
              title: 'Percorsi Sicuri',
              onBack: () {
                 Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const MainScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}


class _StickyHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _StickyHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF).withOpacity(0.9),
            border: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.5),
                  shape: const CircleBorder(),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}