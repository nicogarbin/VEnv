import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DynamicMapScreen extends StatefulWidget {
  const DynamicMapScreen({super.key});

  @override
  State<DynamicMapScreen> createState() => _DynamicMapScreenState();
}

class _DynamicMapScreenState extends State<DynamicMapScreen> {
  List<Polygon> _veneziaPolygons = [];
  List<List<LatLng>> _polygonGeometries = [];
  bool _isLoading = true;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadVeneziaData();
  }

  Future<void> _loadVeneziaData() async {
    try {
      // CARICAMENTO FILE (Assicurati che nel pubspec.yaml ci sia venezia.geojson)
      final String jsonString = await rootBundle.loadString('assets/venezia.geojson');
      
      final Map<String, dynamic> data = jsonDecode(jsonString);
      List<Polygon> polygons = [];
      List<List<LatLng>> geometries = [];

      final fillColor = Colors.blue.withOpacity(0.2);
      final borderColor = Colors.blue.withOpacity(0.8);

      if (data['features'] != null) {
        for (var feature in data['features']) {
          var geometry = feature['geometry'];
          if (geometry == null) continue;

          // Usiamo 'dynamic' per essere più flessibili ed evitare l'errore di cast
          List<dynamic> allPolygonsRaw = [];

          // 1. NORMALIZZAZIONE: Mettiamo tutto in una lista di poligoni
          if (geometry['type'] == 'Polygon') {
            // Un poligono è una lista di anelli. Lo aggiungiamo alla lista generale.
            allPolygonsRaw.add(geometry['coordinates']);
          } else if (geometry['type'] == 'MultiPolygon') {
            // Un multipolygon è già una lista di poligoni. Li aggiungiamo tutti.
            for (var p in geometry['coordinates']) {
              allPolygonsRaw.add(p);
            }
          }

          // 2. ESTRAZIONE PUNTI
          for (var rawPolygon in allPolygonsRaw) {
            // rawPolygon è una lista di anelli (List<List<Coord>>). 
            // Il primo anello [0] è il contorno esterno.
            if (rawPolygon is List && rawPolygon.isNotEmpty) {
              var outerRing = rawPolygon[0];
              List<LatLng> points = [];

              for (var point in outerRing) {
                // point dovrebbe essere [long, lat]
                if (point is List && point.length >= 2) {
                  // GeoJSON usa [Longitudine, Latitudine]
                  // FlutterMap vuole [Latitudine, Longitudine]
                  double lat = point[1].toDouble();
                  double lng = point[0].toDouble();
                  points.add(LatLng(lat, lng));
                }
              }

              if (points.isNotEmpty) {
                polygons.add(
                  Polygon(
                    points: points,
                    color: fillColor,
                    borderColor: borderColor,
                    borderStrokeWidth: 1.5,
                    disableHolesBorder: true,
                    label: feature['properties']?['nome'] ?? "Zona", // Se c'è un nome, lo usiamo dopo
                  ),
                );
                geometries.add(points);
              }
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _veneziaPolygons = polygons;
          _polygonGeometries = geometries;
          _isLoading = false;
          _errorMessage = "";
        });
      }
    } catch (e, stack) {
      print("ERRORE: $e");
      print(stack);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Errore durante la lettura della mappa:\n$e";
        });
      }
    }
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    bool found = false;
    // Iteriamo al contrario per prendere il poligono più in alto (se sovrapposti)
    for (int i = _polygonGeometries.length - 1; i >= 0; i--) {
      if (_isPointInPolygon(point, _polygonGeometries[i])) {
        _showEmptyPopup();
        found = true;
        break;
      }
    }
    
    // Debug: se clicchi fuori
    if (!found) {
      print("Cliccato fuori dalle aree");
    }
  }

  // Algoritmo Ray Casting
  bool _isPointInPolygon(LatLng point, List<LatLng> polygonPoints) {
    int intersectCount = 0;
    for (int i = 0; i < polygonPoints.length - 1; i++) {
      double cathetus1 = polygonPoints[i].latitude;
      double cathetus2 = polygonPoints[i + 1].latitude;
      double cathetus3 = polygonPoints[i].longitude;
      double cathetus4 = polygonPoints[i + 1].longitude;
      if (((cathetus1 > point.latitude) != (cathetus2 > point.latitude)) &&
          (point.longitude < (cathetus4 - cathetus3) * (point.latitude - cathetus1) / (cathetus2 - cathetus1) + cathetus3)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) != 0;
  }

  void _showEmptyPopup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Zona Selezionata"),
        content: const Text("Hai cliccato su un'area di Venezia."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Chiudi"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      body: Stack(
        children: [
          // MAPPA
          Positioned.fill(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_errorMessage, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)))
                    : FlutterMap(
                        options: MapOptions(
                          initialCenter: const LatLng(45.437, 12.332), // Venezia
                          initialZoom: 13.0,
                          minZoom: 10.0,
                          maxZoom: 18.0,
                          onTap: _handleTap,
                          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                          ),
                          PolygonLayer(
                            polygons: _veneziaPolygons,
                          ),
                        ],
                      ),
          ),
          
          // HEADER
          Positioned(
            top: 0, left: 0, right: 0,
            child: _StickyHeader(
              title: 'Mappa Venezia',
              showBack: false,
              onBack: () {},
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
  final bool showBack;
  const _StickyHeader({required this.title, required this.onBack, this.showBack = true});

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
              if (showBack)
                IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)))
              else
                const SizedBox(width: 48),
              Expanded(
                child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }
}