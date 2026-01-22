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

  // --- METODI PER IL METEO (AGGIUNTI) ---
  
  Future<Map<String, dynamic>> _fetchEnvironmentalData(LatLng location) async {
    try {
      // 1. Meteo (Temperatura)
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current=temperature_2m'
      );
      
      // 2. Qualità dell'aria (CAQI - Common Air Quality Index)
      final aqiUrl = Uri.parse(
        'https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${location.latitude}&longitude=${location.longitude}&current=european_aqi'
      );

      final results = await Future.wait([
        http.get(weatherUrl),
        http.get(aqiUrl),
      ]);

      final weatherRes = results[0];
      final aqiRes = results[1];

      double? temperature;
      int? aqi;

      if (weatherRes.statusCode == 200) {
        final data = jsonDecode(weatherRes.body);
        temperature = data['current']?['temperature_2m'];
      }

      if (aqiRes.statusCode == 200) {
        final data = jsonDecode(aqiRes.body);
        aqi = data['current']?['european_aqi'];
      }

      return {
        'temp': temperature,
        'aqi': aqi,
      };
    } catch (e) {
      debugPrint("Errore meteo/aqi: $e");
      return {};
    }
  }

  String _getAqiDescription(int aqi) {
    if (aqi < 30) return "Ottima";
    if (aqi < 60) return "Buona";
    if (aqi < 90) return "Mediocre";
    return "Pessima";
  }

  Color _getAqiColor(int aqi) {
    // Scala Blu (Bene) -> Rosso (Male)
    if (aqi < 40) return Colors.blue; 
    if (aqi < 70) return Colors.blue[900]!; 
    if (aqi < 100) return Colors.red[300]!; 
    return Colors.red; 
  }

  Color _getTempColor(double temp) {
    // Blu per freddo/mite, Rosso per caldo
    if (temp < 10) return Colors.blue[900]!; // Molto Freddo
    if (temp < 25) return Colors.blue;       // Mite/Ok
    if (temp < 30) return Colors.red[300]!;  // Caldo
    return Colors.red;                       // Molto Caldo
  }

  // --- LOGICA INDICE DI RISCHIO ---

  double _calculateRiskIndex(double tideCm, double? temp, int? aqi, double? zoneHeightCm) {
    if (temp == null || aqi == null) return 0.0;
    
    // 1. Marea (60% Peso): Calcolata sulla differenza tra Marea e Altezza Suolo
    double tideScore = 0.0;
    // Se non abbiamo l'altezza della zona, usiamo un default prudente (es. 100cm)
    double threshold = zoneHeightCm ?? 100.0;
    
    double waterLevel = tideCm - threshold; // Cm di acqua sopra il suolo
    
    if (waterLevel > 0) {
      // Se c'è acqua a terra, il rischio sale. 
      // Consideriamo "Critico" (100%) se ci sono più di 15cm d'acqua (servono stivali alti)
      tideScore = (waterLevel / 15.0) * 100.0;
    } else {
      // Se l'acqua è sotto il livello del suolo, rischio marea è 0
      tideScore = 0.0;
    }
    tideScore = tideScore.clamp(0.0, 100.0);

    // 2. Aria (30% Peso): AQI europeo (0-100+)
    double aqiScore = aqi.toDouble().clamp(0.0, 100.0);

    // 3. Temperatura (10% Peso): Discomfort termico
    double tempDelta = (temp - 20).abs();
    double tempScore = (tempDelta * 2.0).clamp(0.0, 100.0);

    // Calcolo Ponderato
    return (tideScore * 0.60) + (aqiScore * 0.30) + (tempScore * 0.10);
  }

  Color _getRiskColor(double score) {
    if (score < 30) return Colors.blue;       // Basso -> Blu
    if (score < 60) return Colors.red[300]!;  // Medio -> Rosso Chiaro
    return Colors.red;                        // Alto -> Rosso Scuro
  }

  String _getRiskLabel(double score) {
    if (score < 30) return "BASSO";
    if (score < 60) return "MODERATO";
    if (score < 80) return "ELEVATO";
    return "CRITICO";
  }

  void _showZonePopup(ZoneModel zone) {
    // Calcolo marea stimata nel centro della zona
    final double? estimatedTide = _estimateTideAtPoint(zone.bounds.center);
    
    // Recupero comunque il dato della stazione ufficiale per confronto (opzionale)
    final officialTide = (zone.stationName != null) ? _tideData[zone.stationName] : null;

    // Future per i dati ambientali
    final environmentalFuture = _fetchEnvironmentalData(zone.bounds.center);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView( // Aggiunto per evitare overflow su schermi piccoli
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Zona ${zone.id ?? 'N/D'}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (zone.stationName != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                      child: Text(zone.stationName!, style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow("Altezza suolo media:", "${zone.meanHeight?.toStringAsFixed(2) ?? '-'} cm"),
              
              const Divider(height: 16),
              
              // --- SEZIONE LIVELLO MAREA ---
              const Text("Livello Marea", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Livello stimato:", style: TextStyle(fontSize: 16)),
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

              const Divider(height: 16),

              // --- NUOVA SEZIONE METEO & ARIA & INDICE RISCHIO ---
              const Text("Indice di Rischio & Ambiente", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
              const SizedBox(height: 12),
              
              FutureBuilder<Map<String, dynamic>>(
                future: environmentalFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  
                  final data = snapshot.data ?? {};
                  final double? temp = data['temp'];
                  final int? aqi = data['aqi'];

                  // Calcolo Indice Unico
                  double riskScore = 0.0;
                  bool hasData = temp != null && aqi != null;
                  if (hasData) {
                    // Ora passiamo anche l'altezza media della zona!
                    riskScore = _calculateRiskIndex(estimatedTide ?? 0, temp, aqi, zone.meanHeight);
                  }

                  if (!hasData) {
                    return const Text("Dati ambientali non disponibili", style: TextStyle(color: Colors.grey));
                  }

                  final riskColor = _getRiskColor(riskScore);

                  return Column(
                    children: [
                      // --- CARD INDICE DI RISCHIO ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: riskColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: riskColor, width: 2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: riskColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "INDICE DI RISCHIO COMPLESSIVO",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: riskColor.withOpacity(0.8), letterSpacing: 1.1),
                                  ),
                                  Text(
                                    _getRiskLabel(riskScore),
                                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: riskColor),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              "${riskScore.toInt()}/100",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: riskColor),
                            ),
                          ],
                        ),
                      ),

                      // --- GRIGLIA DATI AMBIENTALI ---
                      Row(
                        children: [
                          // Box Temperatura
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final tColor = _getTempColor(temp!);
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: tColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: tColor.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.thermostat, color: tColor),
                                      const SizedBox(height: 4),
                                      const Text("Temperatura", style: TextStyle(fontSize: 12, color: Colors.black54)),
                                      Text(
                                        "${temp.toStringAsFixed(1)}°C", 
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                                      ),
                                    ],
                                  ),
                                );
                              }
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Box Qualità Aria
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final aColor = _getAqiColor(aqi!);
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: aColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: aColor.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.air, color: aColor),
                                      const SizedBox(height: 4),
                                      const Text("Qualità Aria", style: TextStyle(fontSize: 12, color: Colors.black54)),
                                      Text(
                                        _getAqiDescription(aqi), 
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                );
                              }
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              
              const SizedBox(height: 16),
            ],
          ),
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
    if (cm > 80) return Colors.red[300]!;
    if (cm > 110) return Colors.red;
    return Colors.blue;
  }

  // Calcola il colore della zona in base all'altezza della marea stimata
  Color _getZoneFillColor(ZoneModel zone) {
    if (_selectedZone == zone) {
      return Colors.red.withOpacity(0.4);
    }
    
    // Default se mancano dati, un colore base
    if (_tideData.isEmpty) return Colors.blue.withOpacity(0.2);

    final double? tide = _estimateTideAtPoint(zone.bounds.center);
    
    if (tide == null) return Colors.blue.withOpacity(0.2);

    // Mappatura dinamica: più alta è la marea, più scuro/opaco è il blu.
    // Range ottimizzato: da 0cm (scuro minimo) a 140cm (scuro massimo).
    double min = 0.0;
    double max = 140.0;
    
    double t = ((tide - min) / (max - min)).clamp(0.0, 1.0);
    
    // Opacità tra 0.1 (chiaro) e 0.9 (molto scuro)
    return Colors.blue.withOpacity(0.1 + (t * 0.8));
  }

  @override
  Widget build(BuildContext context) {
    // Colori costanti per i bordi
    final normalBorder = Colors.blue.withOpacity(0.6);
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
                              // Usa la funzione dinamica per il colore
                              final fillColor = _getZoneFillColor(zone);
                              
                              return Polygon(
                                points: zone.points,
                                color: fillColor,
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