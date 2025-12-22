import 'package:flutter/material.dart';

class DynamicMapScreen extends StatefulWidget {
  const DynamicMapScreen({super.key});

  @override
  State<DynamicMapScreen> createState() => _DynamicMapScreenState();
}

class _DynamicMapScreenState extends State<DynamicMapScreen> {
  @override
  Widget build(BuildContext context) {
    // Non usiamo Scaffold qui perché c'è già nel MainScreen.
    // Usiamo uno Stack per sovrapporre sfondo e barra di ricerca.
    return const Stack(
      children: [
        _MapBackground(), // Sfondo (Mappa)
        _TopSearch(),     // Barra di ricerca sopra la mappa
      ],
    );
  }
}

// --- I TUOI WIDGET ORIGINALI (leggermente ottimizzati) ---

class _MapBackground extends StatelessWidget {
  const _MapBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFFBFDBFE), // Celeste chiaro
            Color(0xFFEFF6FF), // Bianco sporco
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: const Center(
        child: Text(
          'VENICE MAP',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black26, // Colore più scuro per vedersi sullo sfondo chiaro
          ),
        ),
      ),
    );
  }
}

class _TopSearch extends StatelessWidget {
  const _TopSearch();

  @override
  Widget build(BuildContext context) {
    // SafeArea impedisce che la barra finisca sotto l'orologio/notch del telefono
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min, // Occupa solo lo spazio necessario
          children: [
            Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(30),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search Sestiere or Zone',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: const Icon(Icons.tune),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // SingleChildScrollView per evitare errori se i chip sono troppi
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: const [
                  _FilterChip(label: 'Flood Risk', selected: true),
                  _FilterChip(label: 'Tourist Routes'),
                  _FilterChip(label: 'Vaporetto'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;

  const _FilterChip({required this.label, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        backgroundColor: selected ? const Color(0xFF3B82F6) : Colors.white,
        label: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}