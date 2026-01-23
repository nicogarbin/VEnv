import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Rimuoviamo la splash nativa quando siamo pronti a disegnare
    FlutterNativeSplash.remove(); 
    _navigateToHome();
  }

  _navigateToHome() async {
    // Aspetta 2 secondi per mostrare il logo grande
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Lo stesso colore della splash nativa
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0), // Margine per non toccare i bordi
          child: Image.asset(
            'assets/app_icon.png',
            width: 300, // Dimensione grande forzata
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
