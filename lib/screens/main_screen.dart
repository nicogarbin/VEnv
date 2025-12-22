import 'package:flutter/material.dart';
import 'dynamic_map/dynamic_map.dart';
import 'data_history/data_history.dart';
import 'news/news.dart';
import 'alternative_path/alternative_path.dart';



class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DynamicMapScreen(), // La tua mappa ripulita
    const Center(child: Text("News Screen (In costruzione)")),
    const Center(child: Text("Settings Screen (In costruzione)")),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack è FONDAMENTALE per le mappe:
      // Mantiene la mappa "viva" in memoria anche quando cambi tab,
      // così non deve ricaricarsi ogni volta che ci torni sopra.
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Mappa',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.newspaper),
            label: 'News',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}