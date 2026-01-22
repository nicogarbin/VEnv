import 'dart:convert';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // Per 'compute'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

// --- MODELLI DATI ---

/// Modello che rappresenta una zona di Venezia (Dati + Geometria + Bounds)
class ZoneModel {
  final int? id;
  final double? meanHeight;
  final String? stationName;
  final List<LatLng> points;
  final LatLngBounds bounds; // Fondamentale per performance al click

  ZoneModel({
    required this.id,
    required this.meanHeight,
    required this.stationName,
    required this.points,
    required this.bounds,
  });
}

/// Modello per la lettura della marea
class TideReading {
  final String station;
  final double? valueCm; // Valore già convertito in cm
  final String rawValue; // Testo originale per fallback
  final LatLng? location; // Posizione del sensore

  TideReading({
    required this.station,
    required this.valueCm,
    required this.rawValue,
    this.location,
  });

  factory TideReading.fromApi(Map<String, dynamic> json) {
    final stationRaw = json['stazione']?.toString() ?? "";
    final valueRaw = json['valore']?.toString() ?? "N/D";
    
    // Parsing Coordinate
    LatLng? loc;
    try {
      final lat = double.tryParse(json['latDDN']?.toString() ?? "");
      final lon = double.tryParse(json['lonDDE']?.toString() ?? "");
      if (lat != null && lon != null) {
        loc = LatLng(lat, lon);
      }
    } catch (_) {}

    double? cm;
    try {
      // Rimuove caratteri non numerici tranne punto, virgola e meno
      String clean = valueRaw.replaceAll('m', '').trim();
      clean = clean.replaceAll(',', '.');
      double meters = double.parse(clean);
      cm = meters * 100;
    } catch (_) {
      // Parsing fallito, resta null
    }

    return TideReading(
      station: _normalizeStationName(stationRaw),
      valueCm: cm,
      rawValue: valueRaw,
      location: loc,
    );
  }
}

// Funzione helper globale
String _normalizeStationName(String s) {
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// --- LOGICA DI PARSING (ISOLATA) ---

/// Questa funzione deve stare FUORI dalla classe State per essere usata con `compute`
List<ZoneModel> _parseGeoJsonInBackground(String jsonString) {
  final Map<String, dynamic> data = jsonDecode(jsonString);
  List<ZoneModel> results = [];

  if (data['features'] == null) return results;

  for (var feature in data['features']) {
    final props = feature['properties'] as Map<String, dynamic>?;
    final geometry = feature['geometry'];

    if (geometry == null) continue;

    // Estrazione dati
    final int? zoneId = int.tryParse(props?['id']?.toString() ?? "");
    final double? meanHeight = double.tryParse(props?['LIVELLO_PS_mean']?.toString() ?? "");
    final String? stationRaw = props?['rilevatore']?.toString();
    final String? stationName = stationRaw != null ? _normalizeStationName(stationRaw) : null;

    // Estrazione coordinate
    List<List<dynamic>> polygonsRaw = [];
    if (geometry['type'] == 'Polygon') {
      polygonsRaw.add(geometry['coordinates']);
    } else if (geometry['type'] == 'MultiPolygon') {
      for (var p in geometry['coordinates']) {
        polygonsRaw.add(p);
      }
    }

    for (var poly in polygonsRaw) {
      if (poly is List && poly.isNotEmpty) {
        var outerRing = poly[0]; // Primo anello = contorno esterno
        List<LatLng> points = [];
        
        for (var point in outerRing) {
          if (point is List && point.length >= 2) {
            // GeoJSON è [Lon, Lat], LatLng è [Lat, Lon]
            points.add(LatLng(point[1].toDouble(), point[0].toDouble()));
          }
        }

        if (points.isNotEmpty) {
          // Calcolo Bounds per ottimizzazione click
          final bounds = LatLngBounds.fromPoints(points);
          
          results.add(ZoneModel(
            id: zoneId,
            meanHeight: meanHeight,
            stationName: stationName,
            points: points,
            bounds: bounds,
          ));
        }
      }
    }
  }
  return results;
}


// --- WIDGET PRINCIPALE ---

class DynamicMapScreen extends StatefulWidget {
  const DynamicMapScreen({super.key});

  @override
  State<DynamicMapScreen> createState() => _DynamicMapScreenState();
}

class _DynamicMapScreenState extends State<DynamicMapScreen> {
  // Stato Mappa
  List<ZoneModel> _zones = [];
  bool _isLoadingMap = true;
  String _mapError = "";
  
  // Stato Selezione
  ZoneModel? _selectedZone;

  // Stato Maree
  final Map<String, TideReading> _tideData = {};
  bool _isLoadingTide = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    // 1. Carica Mappa (in parallelo)
    _loadMapData();
    // 2. Carica Maree (in parallelo)
    _loadTideData();
  }

  Future<void> _loadMapData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/venezia.geojson');
      
      // Esegue il parsing pesante in un thread separato
      final zones = await compute(_parseGeoJsonInBackground, jsonString);

      if (mounted) {
        setState(() {
          _zones = zones;
          _isLoadingMap = false;
        });
      }
    } catch (e) {
      debugPrint("Errore mappa: $e");
      if (mounted) {
        setState(() {
          _mapError = "Impossibile caricare la mappa.";
          _isLoadingMap = false;
        });
      }
    }
  }

<<<<<<< HEAD
  Future<void> _loadTideData() async {
    try {
      final uri = Uri.parse('https://dati.venezia.it/sites/default/files/dataset/opendata/livello.json');
      final res = await http.get(uri);
      
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        final Map<String, TideReading> tempMap = {};
        
        for (var item in list) {
          if (item is Map<String, dynamic>) {
            final reading = TideReading.fromApi(item);
            if (reading.station.isNotEmpty) {
              tempMap[reading.station] = reading;
=======
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
>>>>>>> af91633d5b250281966be9096166cbb5e1d80298
            }
          }
        }
        
        if (mounted) {
          setState(() {
            _tideData.addAll(tempMap);
            _isLoadingTide = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Errore maree: $e");
      // Non blocchiamo la UI, semplicemente i dati non ci saranno
      if (mounted) setState(() => _isLoadingTide = false);
    }
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    ZoneModel? foundZone;

    // Iteriamo al contrario (Z-index: quelli disegnati dopo sono sopra)
    for (final zone in _zones.reversed) {
      // 1. CHECK VELOCE: Il punto è nel rettangolo della zona?
      if (!zone.bounds.contains(point)) continue;

      // 2. CHECK PRECISO: Ray Casting
      if (_isPointInPolygon(point, zone.points)) {
        foundZone = zone;
        break; // Trovato!
      }
    }

    if (foundZone != null) {
      setState(() {
        _selectedZone = foundZone; // Evidenzia la zona
      });
      _showZonePopup(foundZone);
    } else {
      // Se clicco fuori, deseleziono
      if (_selectedZone != null) {
        setState(() {
          _selectedZone = null;
        });
      }
    }
  }

  // Algoritmo Ray Casting standard
  bool _isPointInPolygon(LatLng point, List<LatLng> polygonPoints) {
    int intersectCount = 0;
    for (int i = 0; i < polygonPoints.length - 1; i++) {
      double p1Lat = polygonPoints[i].latitude;
      double p1Lon = polygonPoints[i].longitude;
      double p2Lat = polygonPoints[i + 1].latitude;
      double p2Lon = polygonPoints[i + 1].longitude;

      if (((p1Lat > point.latitude) != (p2Lat > point.latitude)) &&
          (point.longitude < (p2Lon - p1Lon) * (point.latitude - p1Lat) / (p2Lat - p1Lat) + p1Lon)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) != 0;
  }

  /// Calcola la marea stimata in un punto usando Inverse Distance Weighting (IDW)
  /// Interpolazione spaziale basata su tutti i sensori disponibili.
  double? _estimateTideAtPoint(LatLng point) {
    if (_tideData.isEmpty) return null;

    double numerator = 0.0;
    double denominator = 0.0;
    const double power = 2.0; // Esponente per il peso della distanza (solitamente 2)
    const Distance distanceCalc = Distance();

    int validSensors = 0;

    for (final reading in _tideData.values) {
      if (reading.valueCm == null || reading.location == null) continue;

      final double dist = distanceCalc.as(LengthUnit.Meter, point, reading.location!);
      
      // Se siamo esattamente sopra un sensore (distanza ~0), usiamo quel valore
      if (dist < 1.0) return reading.valueCm;

      final double weight = 1.0 / (dist * dist); // 1 / d^2
      
      numerator += reading.valueCm! * weight;
      denominator += weight;
      validSensors++;
    }

    if (validSensors == 0 || denominator == 0) return null;

    return numerator / denominator;
  }

  void _showZonePopup(ZoneModel zone) {
    // Calcolo marea stimata nel centro della zona
    final double? estimatedTide = _estimateTideAtPoint(zone.bounds.center);
    
    // Recupero comunque il dato della stazione ufficiale per confronto (opzionale)
    final officialTide = (zone.stationName != null) ? _tideData[zone.stationName] : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Zona ${zone.id ?? 'N/D'}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _infoRow("Altezza suolo media:", "${zone.meanHeight?.toStringAsFixed(2) ?? '-'} cm"),
            _infoRow("Stazione rif.:", zone.stationName ?? "Nessuna"),
            
            const Divider(height: 24),
            if (_isLoadingTide)
              const Center(child: LinearProgressIndicator())
            else 
              Column(
                children: [
                  // Marea Stimata (Calcolata)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Livello stimato (interpolato):", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(
                        estimatedTide != null ? "${estimatedTide.toStringAsFixed(1)} cm" : "N/D",
                        style: TextStyle(
                          fontSize: 22, 
                          fontWeight: FontWeight.bold,
                          color: estimatedTide != null ? _getTideColor(estimatedTide) : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Marea Stazione Ufficiale (Piccolo, per riferimento)
                  if (zone.stationName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Sensore ${zone.stationName}:", style: const TextStyle(fontSize: 13, color: Colors.black54)),
                          Text(
                            (officialTide != null && officialTide.valueCm != null) 
                                ? "${officialTide.valueCm!.toStringAsFixed(1)} cm" 
                                : "Dati non disponibili",
                            style: TextStyle(
                              fontSize: 13, 
                              fontWeight: FontWeight.w500,
                              color: (officialTide != null && officialTide.valueCm != null) 
                                  ? Colors.black87 
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).whenComplete(() {
      // Deseleziona quando chiudi il popup
      setState(() => _selectedZone = null);
    });
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _getTideColor(double cm) {
    if (cm > 80) return Colors.orange;
    if (cm > 110) return Colors.red;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    // Colori costanti
    final normalFill = Colors.blue.withOpacity(0.2);
    final normalBorder = Colors.blue.withOpacity(0.6);
    final selectedFill = Colors.red.withOpacity(0.4);
    final selectedBorder = Colors.red;

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      body: Stack(
        children: [
          // MAPPA
          Positioned.fill(
            child: _isLoadingMap
                ? const Center(child: CircularProgressIndicator())
                : _mapError.isNotEmpty
                    ? Center(child: Text(_mapError))
                    : FlutterMap(
                        options: MapOptions(
                          initialCenter: const LatLng(45.4376, 12.3304), // Venezia
                          initialZoom: 13.0,
                          minZoom: 13.0, // Bloccato come richiesto
                          maxZoom: 13.0, // Bloccato come richiesto
                          onTap: _handleTap,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none, // Mappa bloccata (no pan/zoom)
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                          ),
                          PolygonLayer(
                            polygons: _zones.map((zone) {
                              final isSelected = _selectedZone == zone;
                              return Polygon(
                                points: zone.points,
                                color: isSelected ? selectedFill : normalFill,
                                borderColor: isSelected ? selectedBorder : normalBorder,
                                borderStrokeWidth: isSelected ? 3.0 : 1.0,
                                isFilled: true,
                                label: null, // Disabilitiamo label per performance
                              );
                            }).toList(),
                          ),
                        ],
                      ),
          ),
          
          // HEADER (Mantenuto il tuo stile)
          Positioned(
            top: 0, left: 0, right: 0,
            child: _StickyHeader(
              title: 'Mappa Venezia',
              onBack: () {}, // Gestisci navigazione se necessario
              showBack: false,
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
    final topPadding = MediaQuery.of(context).padding.top;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, topPadding + 12, 16, 12),
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
