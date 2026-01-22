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

/// Modello per caching dati ambientali (per stima val mancanti)
class EnvironmentalReading {
  final LatLng location;
  final double? temp;
  final double? uv;
  final int? aqi;

  EnvironmentalReading({required this.location, this.temp, this.uv, this.aqi});
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
      if (poly.isNotEmpty) {
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

  // Cache Dati Ambientali (per stima)
  final List<EnvironmentalReading> _cachedEnvData = [];

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
    double? temperature;
    double? uvIndex;
    int? aqi;
    
    bool apiSuccess = false;

    try {
      // 1. Meteo (Temperatura e UV)
      final weatherUrl = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${location.latitude}&longitude=${location.longitude}&current=temperature_2m,uv_index'
      );
      
      // 2. Qualità dell'aria (CAQI - Common Air Quality Index)
      final aqiUrl = Uri.parse(
        'https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${location.latitude}&longitude=${location.longitude}&current=european_aqi'
      );

      final results = await Future.wait([
        http.get(weatherUrl),
        http.get(aqiUrl),
      ]).timeout(const Duration(seconds: 5)); // Timeout rapido per evitare blocchi

      final weatherRes = results[0];
      final aqiRes = results[1];

      if (weatherRes.statusCode == 200) {
        final data = jsonDecode(weatherRes.body);
        temperature = data['current']?['temperature_2m'];
        uvIndex = data['current']?['uv_index'];
      }

      if (aqiRes.statusCode == 200) {
        final data = jsonDecode(aqiRes.body);
        aqi = data['current']?['european_aqi'];
      }
      
      apiSuccess = true;
    } catch (e) {
      debugPrint("Errore meteo/aqi: $e");
    }

    // Salva in cache SOLO se abbiamo dati reali (almeno uno)
    if (apiSuccess && (temperature != null || uvIndex != null || aqi != null)) {
      _cachedEnvData.add(EnvironmentalReading(
        location: location,
        temp: temperature,
        uv: uvIndex,
        aqi: aqi,
      ));
    }

    // --- LOGICA DI RECUPERO e STIMA ---
    bool tempEst = false;
    bool uvEst = false;
    bool aqiEst = false;

    // Se mancano dati (o API fallita), proviamo a Stimare dai vicini
    if (temperature == null || uvIndex == null || aqi == null) {
      final estimates = _estimateEnvFromCache(location);
      
      if (temperature == null && estimates['temp'] != null) {
        temperature = estimates['temp'];
        tempEst = true;
      }
      if (uvIndex == null && estimates['uv'] != null) {
        uvIndex = estimates['uv'];
        uvEst = true;
      }
      if (aqi == null && estimates['aqi'] != null) {
        aqi = estimates['aqi']?.toInt();
        aqiEst = true;
      }
    }

    return {
      'temp': temperature,
      'uv': uvIndex,
      'aqi': aqi,
      'temp_est': tempEst,
      'uv_est': uvEst,
      'aqi_est': aqiEst,
    };
  }
  
  /// Stima valori ambientali usando IDW sui dati in cache
  Map<String, double?> _estimateEnvFromCache(LatLng point) {
    if (_cachedEnvData.isEmpty) return {'temp': null, 'uv': null, 'aqi': null};

    double numTemp = 0, denTemp = 0;
    double numUv = 0, denUv = 0;
    double numAqi = 0, denAqi = 0;
    
    const Distance distCalc = Distance();

    for (var r in _cachedEnvData) {
      double dist = distCalc.as(LengthUnit.Meter, point, r.location);
      if (dist < 1.0) dist = 1.0; 
      
      // Peso inversamente proporzionale alla distanza^2
      double weight = 1.0 / (dist * dist);

      if (r.temp != null) { numTemp += r.temp! * weight; denTemp += weight; }
      if (r.uv != null) { numUv += r.uv! * weight; denUv += weight; }
      if (r.aqi != null) { numAqi += r.aqi!.toDouble() * weight; denAqi += weight; }
    }

    return {
      'temp': denTemp > 0 ? numTemp / denTemp : null,
      'uv': denUv > 0 ? numUv / denUv : null,
      'aqi': denAqi > 0 ? numAqi / denAqi : null,
    };
  }

  String _getAqiDescription(int aqi) {
    if (aqi < 30) return "Ottima";
    if (aqi < 60) return "Buona";
    if (aqi < 90) return "Mediocre";
    return "Pessima";
  }

  Color _getAqiColor(int aqi) {
    // Scala Verde (Bene) -> Rosso (Male)
    if (aqi < 40) return Colors.green; 
    if (aqi < 70) return Colors.orange; 
    if (aqi < 100) return Colors.red[300]!; 
    return Colors.red; 
  }

  Color _getTempColor(double temp) {
    // Scala Verde (Comfort) -> Rosso (Discomfort)
    // Ho allargato i range per non segnare subito rosso il freddo moderato
    if (temp >= 15 && temp <= 27) return Colors.green; // Comfort
    if (temp >= 5 && temp < 35) return Colors.orange; // Un po' freddo o caldo
    return Colors.red; // Gelo (<5) o Caldo torrido (>35)
  }
  
  Color _getUvColor(double uv) {
    if (uv < 4) return Colors.green; // Basso
    if (uv < 7) return Colors.orange; // Moderato/Alto
    return Colors.red; // Molto Alto/Estremo
  }

  // --- LOGICA INDICE DI RISCHIO ---

  double _calculateRiskIndex(double tideCm, double? temp, int? aqi, double? uv, double? zoneHeightCm) {
    if (temp == null || aqi == null) return 0.0;
    
    // 1. Marea (50% Peso): Calcolata sulla differenza tra Marea e Altezza Suolo
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

    // 2. Aria (25% Peso): AQI europeo (0-100+)
    double aqiScore = aqi.toDouble().clamp(0.0, 100.0);

    // 3. Raggi UV (15% Peso): Scala 0-11+
    double uvScore = 0.0;
    if (uv != null) {
      uvScore = (uv / 11.0) * 100.0;
      uvScore = uvScore.clamp(0.0, 100.0);
    }

    // 4. Temperatura (10% Peso): Discomfort termico
    double tempDelta = (temp - 20).abs();
    double tempScore = (tempDelta * 2.0).clamp(0.0, 100.0);

    // Calcolo Ponderato
    return (tideScore * 0.50) + (aqiScore * 0.25) + (uvScore * 0.15) + (tempScore * 0.10);
  }

  Color _getRiskColor(double score) {
    if (score < 30) return Colors.green;       // Basso -> Verde
    if (score < 60) return Colors.orange;  // Medio -> Arancione
    return Colors.red;                        // Alto -> Rosso
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
                  final double? uv = data['uv'];
                  final int? aqi = data['aqi'];

                  // Flag se sono stimati
                  final bool isTempEst = data['temp_est'] == true;
                  final bool isUvEst = data['uv_est'] == true;
                  final bool isAqiEst = data['aqi_est'] == true;

                  final bool anyEstimated = isTempEst || isUvEst || isAqiEst;

                  // Calcolo Indice Unico (Usa i valori solo se disponibili)
                  double riskScore = 0.0;
                  bool hasData = temp != null && aqi != null; // UV è opzionale nella formula precedente ma meglio averlo
                  
                  if (hasData) {
                    riskScore = _calculateRiskIndex(estimatedTide ?? 0, temp, aqi, uv, zone.meanHeight);
                  }

                  if (!hasData) {
                     return const Padding(
                       padding: EdgeInsets.symmetric(vertical: 20),
                       child: Center(child: Text("Dati ambientali non disponibili", style: TextStyle(color: Colors.grey))),
                     );
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
                                  if (anyEstimated)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        "* Valori mancanti stimati",
                                        style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.black45),
                                      ),
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
                                final tColor = _getTempColor(temp);
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
                                      if (isTempEst)
                                        const Text("(stimato)", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
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
                                final aColor = _getAqiColor(aqi);
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
                                      if (isAqiEst)
                                        const Text("(stimato)", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
                                    ],
                                  ),
                                );
                              }
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Box Raggi UV
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final uColor = (uv != null) ? _getUvColor(uv) : Colors.grey;
                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: uColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: uColor.withOpacity(0.3)),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.wb_sunny, color: uColor),
                                      const SizedBox(height: 4),
                                      const Text("Raggi UV", style: TextStyle(fontSize: 12, color: Colors.black54)),
                                      Text(
                                        uv != null ? uv.toStringAsFixed(1) : "N/D", 
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                                      ),
                                      if (isUvEst)
                                        const Text("(stimato)", style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey)),
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
    const selectedBorder = Colors.red;

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
                            retinaMode: RetinaMode.isHighDensity(context), // Attiva alta risoluzione su schermi HD
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