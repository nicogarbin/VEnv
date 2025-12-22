import 'dart:ui';
import 'package:flutter/material.dart';
import '../main_screen.dart';

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      body: Stack(
        children: [

          ListView(
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
            children: [
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Icon(Icons.newspaper, size: 80, color: Colors.blue.shade300),
                    const SizedBox(height: 20),
                    const Text(
                      'Ultime Notizie',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Qui appariranno le notizie aggiornate su Venezia.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),

                    for (int i = 0; i < 10; i++)
                      Container(
                        height: 100,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      )
                  ],
                ),
              ),
            ],
          ),


          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _StickyHeader(
              title: 'Notizie Venezia',
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

  const _StickyHeader({
    required this.title,
    required this.onBack,
  });

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