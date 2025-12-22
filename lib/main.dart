import 'package:flutter/material.dart';
import 'screens/main_screen.dart'; // Importiamo il nuovo contenitore

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Venice App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(), // <-- Deve puntare qui!
    );
  }
}