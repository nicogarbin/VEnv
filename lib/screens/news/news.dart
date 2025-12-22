import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main_screen.dart';

class NewsScreen extends StatelessWidget {
  const NewsScreen({super.key});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il link.')),
      );
    }
  }

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

                    const SizedBox(height: 16),

                    _NewsLinkCard(
                      title: 'Comune di Venezia',
                      subtitle: 'Sito ufficiale',
                      icon: Icons.public,
                      onTap: () => _openLink(context, 'https://www.comune.venezia.it/'),
                    ),
                    _NewsLinkCard(
                      title: 'Venezia Today',
                      subtitle: 'Notizie sulla marea',
                      icon: Icons.directions_boat,
                      onTap: () => _openLink(context, 'https://www.veneziatoday.it/tag/marea/'),
                    ),
                    _NewsLinkCard(
                      title: 'Protezione Civile',
                      subtitle: 'Avvisi e comunicazioni',
                      icon: Icons.warning_amber_rounded,
                      onTap: () => _openLink(context, 'https://protezionecivile.cittametropolitana.ve.it/news.html/'),
                    ),
                    _NewsLinkCard(
                      title: 'Notizie ISPRA',
                      subtitle: 'Notizie ambientali',
                      icon: Icons.cloud,
                      onTap: () => _openLink(context, 'https://www.venezia.isprambiente.it/news/'),
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

class _NewsLinkCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _NewsLinkCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFF0F172A)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}