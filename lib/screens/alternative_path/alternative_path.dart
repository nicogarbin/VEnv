import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

// --- MODELLI DATI PER RISCHIO ---

/// Modello che rappresenta una zona di Venezia
class _ZoneModel {
  final int? id;
  final double? meanHeight;
  final String? stationName;
  final List<LatLng> points;
  final _LatLngBounds bounds;

  _ZoneModel({
    required this.id,
    required this.meanHeight,
    required this.stationName,
    required this.points,
    required this.bounds,
  });
}

/// Bounds semplificato per LatLng di google_maps_flutter
class _LatLngBounds {
  final double minLat, maxLat, minLng, maxLng;
  
  _LatLngBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  factory _LatLngBounds.fromPoints(List<LatLng> points) {
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLng = double.infinity, maxLng = -double.infinity;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return _LatLngBounds(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }

  bool contains(LatLng point) {
    return point.latitude >= minLat && point.latitude <= maxLat &&
           point.longitude >= minLng && point.longitude <= maxLng;
  }

  LatLng get center => LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
}

/// Modello per la lettura della marea
class _TideReading {
  final String station;
  final double? valueCm;
  final LatLng? location;

  _TideReading({required this.station, required this.valueCm, this.location});

  factory _TideReading.fromApi(Map<String, dynamic> json) {
    final stationRaw = json['stazione']?.toString() ?? "";
    final valueRaw = json['valore']?.toString() ?? "N/D";
    
    LatLng? loc;
    try {
      final lat = double.tryParse(json['latDDN']?.toString() ?? "");
      final lon = double.tryParse(json['lonDDE']?.toString() ?? "");
      if (lat != null && lon != null) loc = LatLng(lat, lon);
    } catch (_) {}

    double? cm;
    try {
      String clean = valueRaw.replaceAll('m', '').trim().replaceAll(',', '.');
      cm = double.parse(clean) * 100;
    } catch (_) {}

    return _TideReading(
      station: stationRaw.replaceAll(RegExp(r'\s+'), ' ').trim(),
      valueCm: cm,
      location: loc,
    );
  }
}

// Funzione di parsing GeoJSON (per compute)
List<_ZoneModel> _parseGeoJsonInBackground(String jsonString) {
  final Map<String, dynamic> data = jsonDecode(jsonString);
  List<_ZoneModel> results = [];

  if (data['features'] == null) return results;

  for (var feature in data['features']) {
    final props = feature['properties'] as Map<String, dynamic>?;
    final geometry = feature['geometry'];
    if (geometry == null) continue;

    final int? zoneId = int.tryParse(props?['id']?.toString() ?? "");
    final double? meanHeight = double.tryParse(props?['LIVELLO_PS_mean']?.toString() ?? "");
    final String? stationRaw = props?['rilevatore']?.toString();
    final String? stationName = stationRaw?.replaceAll(RegExp(r'\s+'), ' ').trim();

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
        var outerRing = poly[0];
        List<LatLng> points = [];
        for (var point in outerRing) {
          if (point is List && point.length >= 2) {
            points.add(LatLng(point[1].toDouble(), point[0].toDouble()));
          }
        }
        if (points.isNotEmpty) {
          results.add(_ZoneModel(
            id: zoneId,
            meanHeight: meanHeight,
            stationName: stationName,
            points: points,
            bounds: _LatLngBounds.fromPoints(points),
          ));
        }
      }
    }
  }
  return results;
}

class AlternativePathScreen extends StatefulWidget {
  const AlternativePathScreen({super.key});

  @override
  State<AlternativePathScreen> createState() => _AlternativePathScreenState();
}

class _AlternativePathScreenState extends State<AlternativePathScreen> {
  // Palette colori allineata con le altre schermate
  final Color freshPrimary = Colors.blue;
  final Color freshText = const Color(0xFF0F172A);
  final Color freshMuted = Colors.grey;

  // Map State
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _startSearchController = TextEditingController();

  static const CameraPosition _kVenice = CameraPosition(
    target: LatLng(45.4408, 12.3155),
    zoom: 14.0,
  );

  // Coordinate dinamiche
  LatLng? _startLocation; // Posizione utente
  LatLng? _endLocation; // Destinazione selezionata
  bool _isLoadingLocation = false;

  // Dati percorso dinamici
  bool _isRouteCalculated = false;
  bool _isCalculatingRoute = false;
  String _routeDuration = "--";
  String _routeDistance = "--";
  String _routeDistanceUnit = "";

  // Dati zone e maree per calcolo rischio
  List<_ZoneModel> _zones = [];
  final Map<String, _TideReading> _tideData = {};
  bool _isRiskDataLoaded = false;

  // ========== MODALITÀ TEST ==========
  final bool _testMode = true;

  final Map<int, double> _testTideLevels = {
    19: 138,
  };
  // ===================================

  @override
  void initState() {
    super.initState();
    _loadRiskData();
  }

  /// Carica i dati per il calcolo del rischio (zone + maree)
  Future<void> _loadRiskData() async {
    await Future.wait([
      _loadZonesData(),
      _loadTideData(),
    ]);
    if (mounted) {
      setState(() => _isRiskDataLoaded = true);
    }
  }

  Future<void> _loadZonesData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/venezia.geojson');
      final zones = await compute(_parseGeoJsonInBackground, jsonString);
      if (mounted) {
        setState(() => _zones = zones);
      }
    } catch (e) {
      debugPrint("Errore caricamento zone: $e");
    }
  }

  Future<void> _loadTideData() async {
    try {
      final uri = Uri.parse('https://dati.venezia.it/sites/default/files/dataset/opendata/livello.json');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body);
        for (var item in list) {
          if (item is Map<String, dynamic>) {
            final reading = _TideReading.fromApi(item);
            if (reading.station.isNotEmpty) {
              _tideData[reading.station] = reading;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Errore caricamento maree: $e");
    }
  }

  /// Stima marea in un punto usando IDW (Inverse Distance Weighting)
  double? _estimateTideAtPoint(LatLng point) {
    // ========== MODALITÀ TEST ==========
    // Se modalità test attiva, usa valori simulati per zone specifiche
    if (_testMode) {
      final zone = _findZoneAtPoint(point);
      if (zone?.id != null && _testTideLevels.containsKey(zone!.id)) {
        final testLevel = _testTideLevels[zone.id]!;
        debugPrint("TEST MODE: Zona ${zone.id} - Marea simulata: $testLevel cm");
        return testLevel;
      }
      // Se la zona non è nei test, continua con calcolo normale
    }
    // ===================================
    
    if (_tideData.isEmpty) return null;

    double numerator = 0.0;
    double denominator = 0.0;
    int validSensors = 0;

    for (final reading in _tideData.values) {
      if (reading.valueCm == null || reading.location == null) continue;

      final double dist = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        reading.location!.latitude, reading.location!.longitude,
      );

      if (dist < 1.0) return reading.valueCm;

      final double weight = 1.0 / (dist * dist);
      numerator += reading.valueCm! * weight;
      denominator += weight;
      validSensors++;
    }

    if (validSensors == 0 || denominator == 0) return null;
    return numerator / denominator;
  }

  /// Trova la zona che contiene un punto
  _ZoneModel? _findZoneAtPoint(LatLng point) {
    for (final zone in _zones.reversed) {
      if (!zone.bounds.contains(point)) continue;
      if (_isPointInPolygon(point, zone.points)) return zone;
    }
    return null;
  }

  /// Ray casting per verificare se un punto è in un poligono
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
  
  // 0=Verde (<20), 1=Giallo (<50), 2=Arancio (<80), 3=Rosso
  int _getRiskTier(double risk) {
    if (risk < 20) return 0;
    if (risk < 50) return 1;
    if (risk < 80) return 2;
    return 3;
  }

  /// Calcola il rischio in un punto (0-100)
  double _calculateRiskAtPoint(LatLng point) {
    final zone = _findZoneAtPoint(point);
    final tide = _estimateTideAtPoint(point);

    if (tide == null) return 0.0;

    // Altezza media del suolo nella zona (default 100cm se non disponibile)
    double threshold = zone?.meanHeight ?? 100.0;

    // Cm di acqua sopra il suolo
    double waterLevel = tide - threshold;

    if (waterLevel <= 0) return 0.0; // Asciutto

    // Rischio proporzionale: 15cm+ = rischio massimo
    double risk = (waterLevel / 15.0) * 100.0;
    return risk.clamp(0.0, 100.0);
  }

  /// Ottiene il colore basato sul rischio
  Color _getRiskColor(double risk) {
    if (risk < 20) return Colors.green;         // Sicuro
    if (risk < 50) return Colors.yellow[700]!;  // Attenzione
    if (risk < 80) return Colors.orange;        // Rischio
    return Colors.red;                          // Pericolo
  }

  /// Crea polylines segmentate per rischio
  Set<Polyline> _createRiskColoredPolylines(List<LatLng> points) {
    Set<Polyline> polylines = {};
    
    if (points.length < 2) return polylines;

    List<LatLng> currentSegment = [points[0]];
    double currentRisk = _calculateRiskAtPoint(points[0]);
    Color currentColor = _getRiskColor(currentRisk);
    int segmentId = 0;

    for (int i = 1; i < points.length; i++) {
      double pointRisk = _calculateRiskAtPoint(points[i]);
      Color pointColor = _getRiskColor(pointRisk);

      if (pointColor == currentColor) {
        currentSegment.add(points[i]);
      } else {
        // Chiudi segmento corrente
        currentSegment.add(points[i]); // Overlap per continuità
        polylines.add(Polyline(
          polylineId: PolylineId('route_$segmentId'),
          points: List.from(currentSegment),
          color: currentColor,
          width: 6,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ));
        
        // Inizia nuovo segmento
        segmentId++;
        currentSegment = [points[i]];
        currentColor = pointColor;
        currentRisk = pointRisk;
      }
    }

    // Aggiungi ultimo segmento
    if (currentSegment.isNotEmpty) {
      polylines.add(Polyline(
        polylineId: PolylineId('route_$segmentId'),
        points: currentSegment,
        color: currentColor,
        width: 6,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ));
    }

    return polylines;
  }
  int _routeDurationMinutes = 0;

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _getUserLocation(); // Ottieni posizione all'avvio
  }

  Future<void> _getUserLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      // Verifica permessi
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Servizi di localizzazione disabilitati")),
          );
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Permesso di localizzazione negato")),
            );
          }
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Permesso di localizzazione negato permanentemente")),
          );
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // Ottieni posizione
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        _startLocation = LatLng(position.latitude, position.longitude);
        _isLoadingLocation = false;
        _startSearchController.text = "La tua posizione";
      });

      // Aggiorna marker partenza
      _updateStartMarker();

      // Sposta camera sulla posizione utente
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(_startLocation!),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore nel recupero della posizione: $e")),
        );
      }
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _updateStartMarker() {
    if (_startLocation != null) {
      _markers.removeWhere((marker) => marker.markerId.value == 'start');
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _startLocation!,
          infoWindow: const InfoWindow(title: 'La tua posizione'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }
  }

  Future<void> _startNavigation() async {
    // Verifica che entrambe le posizioni siano disponibili
    if (_startLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Posizione di partenza non disponibile")),
        );
      }
      return;
    }

    if (_endLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Seleziona una destinazione")),
        );
      }
      return;
    }

    // 1. Setup Markers e stato caricamento
    setState(() {
      _isCalculatingRoute = true;
      _markers.clear();
      _polylines.clear();
      
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _startLocation!,
          infoWindow: const InfoWindow(title: 'Partenza'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _endLocation!,
          infoWindow: InfoWindow(title: _searchController.text),
        ),
      );
    });

    final String? googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (googleApiKey == null || googleApiKey.isEmpty) {
      if (mounted) _showErrorSnackBar("API Key non configurata");
      return;
    }

    try {
      // 1. Ottieni percorsi standard (con alternative)
      var allRoutes = await _getGoogleRoutes(
        _startLocation!, 
        _endLocation!, 
        googleApiKey, 
        alternatives: true
      );

      // 2. Analisi iniziale: il percorso "migliore" standard è sicuro?
      // Se il miglior percorso standard ha un rischio > 0, proviamo a calcolare deviazioni
      bool needsDetour = false;
      if (_isRiskDataLoaded && _zones.isNotEmpty && allRoutes.isNotEmpty) {
         // Analizziamo il maxRisk del migliore standard
         double standardMinMaxRisk = double.infinity;
         for (var route in allRoutes) {
            double risk = _calculateRouteMaxRisk(route);
            if (risk < standardMinMaxRisk) standardMinMaxRisk = risk;
         }
         
         // Se il rischio è Giallo o peggio (>20), cerchiamo deviazioni sicure
         if (standardMinMaxRisk > 20) {
            needsDetour = true;
            debugPrint("⚠️ Percorsi standard rischiosi (MaxRisk: $standardMinMaxRisk). Cerco deviazioni sicure...");
            if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                 const SnackBar(
                   content: Text("Cerco percorsi alternativi sicuri..."), 
                   duration: Duration(milliseconds: 1500)
                 )
               );
            }
         }
      }

      // 3. (Opzionale) Safe Detour Search
      if (needsDetour) {
         final detours = await _findSafeDetourRoutes(_startLocation!, _endLocation!, googleApiKey);
         if (detours.isNotEmpty) {
           debugPrint("✅ Trovati ${detours.length} percorsi deviati sicuri.");
           allRoutes.addAll(detours);
         } else {
           debugPrint("❌ Nessuna deviazione sicura trovata.");
         }
      }

      if (allRoutes.isNotEmpty) {
        // Analisi finale di TUTTI i percorsi (Standard + Deviazioni)
        _analyzeAndSelectBestRoute(allRoutes);
      } else {
        _handleRouteError("ZERO_RESULTS", "Nessun percorso trovato");
      }

    } catch (e) {
       _handleNetworkError(e);
    }
  }

  /// Recupera percorsi da Google Directions API
  Future<List<dynamic>> _getGoogleRoutes(
    LatLng start, 
    LatLng end, 
    String apiKey, 
    {bool alternatives = false, LatLng? waypoint}
  ) async {
    String url = 'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${start.latitude},${start.longitude}'
        '&destination=${end.latitude},${end.longitude}'
        '&mode=walking'
        '&key=$apiKey';
    
    if (alternatives) url += '&alternatives=true';
    if (waypoint != null) {
      // Usiamo 'via:' per non creare uno stopover che divide il percorso in legs
      url += '&waypoints=via:${waypoint.latitude},${waypoint.longitude}';
    }

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (data['status'] == 'OK') {
      return data['routes'] as List<dynamic>;
    }
    return [];
  }

  /// Cerca percorsi alternativi passando per "Punti Sicuri"
  Future<List<dynamic>> _findSafeDetourRoutes(LatLng start, LatLng end, String apiKey) async {
    List<dynamic> detourRoutes = [];
    
    // 1. Identifica Zone Sicure Candidate
    // Cerchiamo zone con Rischio 0 che siano "utili" (non troppo lontane dall'area di interesse)
    List<_ZoneModel> safeCandidates = [];
    
    // Bounding Box allargato dell'area di viaggio
    double minLat = (start.latitude < end.latitude ? start.latitude : end.latitude) - 0.01;
    double maxLat = (start.latitude > end.latitude ? start.latitude : end.latitude) + 0.01;
    double minLng = (start.longitude < end.longitude ? start.longitude : end.longitude) - 0.01;
    double maxLng = (start.longitude > end.longitude ? start.longitude : end.longitude) + 0.01;

    for (var zone in _zones) {
      // Deve essere dentro il bounding box
      if (zone.bounds.center.latitude < minLat || zone.bounds.center.latitude > maxLat) continue;
      if (zone.bounds.center.longitude < minLng || zone.bounds.center.longitude > maxLng) continue;
      
      // Deve essere SICURA (Rischio 0)
      if (_calculateRiskAtPoint(zone.bounds.center) < 10) { // Tolleranza: quasi asciutta
        safeCandidates.add(zone);
      }
    }

    if (safeCandidates.isEmpty) return [];

    // 2. Seleziona 2-3 waypoint strategici dai candidati
    // Ordiniamo per distanza dal centro del percorso per non deviare troppo?
    // O prendiamo punti "laterali"? Facciamo shuffle per casualità (simil-Monte Carlo)
    safeCandidates.shuffle();
    var selectedWaypoints = safeCandidates.take(3).map((z) => z.bounds.center).toList();

    // 3. Richiedi percorsi per questi waypoint
    for (var wp in selectedWaypoints) {
       var routes = await _getGoogleRoutes(start, end, apiKey, waypoint: wp);
       detourRoutes.addAll(routes);
    }

    return detourRoutes;
  }

  double _calculateRouteMaxRisk(dynamic route) {
     List<LatLng> points = _getDetailedPoints(route);
     double maxRisk = 0.0;
     for (var p in points) {
        double r = _calculateRiskAtPoint(p);
        if (r > maxRisk) maxRisk = r;
     }
     return maxRisk;
  }

  List<LatLng> _getDetailedPoints(dynamic route) {
      List<LatLng> allPoints = [];
      if (route['legs'] != null) {
        for (var leg in route['legs']) {
          if (leg['steps'] != null) {
            for (var step in leg['steps']) {
              String? p = step['polyline']?['points'];
              if (p != null) {
                var decoded = PolylinePoints.decodePolyline(p);
                allPoints.addAll(decoded.map((x) => LatLng(x.latitude, x.longitude)));
              }
            }
          }
        }
      }
      if (allPoints.isEmpty && route['overview_polyline']?['points'] != null) {
        var decoded = PolylinePoints.decodePolyline(route['overview_polyline']['points']);
        allPoints = decoded.map((x) => LatLng(x.latitude, x.longitude)).toList();
      }
      return allPoints;
  }

  void _analyzeAndSelectBestRoute(List<dynamic> routes) {
        Map<String, dynamic>? bestRoute;
        List<LatLng>? bestRoutePoints;
        
        List<Map<String, dynamic>> analyzedRoutes = [];

        // Analisi
        if (_isRiskDataLoaded && _zones.isNotEmpty) {
           for (var route in routes) {
              List<LatLng> points = _getDetailedPoints(route);
              double maxRisk = 0.0;
              double totalRisk = 0.0;
              
              for (var p in points) {
                double r = _calculateRiskAtPoint(p);
                if (r > maxRisk) maxRisk = r;
                if (r > 0) totalRisk += r;
              }
              
              // Calcola durata totale (somma delle legs se ci sono waypoint)
              int totalDuration = 0;
              if (route['legs'] != null) {
                for(var leg in route['legs']) {
                   totalDuration += (leg['duration']?['value'] ?? 0) as int;
                }
              }

              analyzedRoutes.add({
                'route': route,
                'points': points,
                'maxRisk': maxRisk,
                'totalRisk': totalRisk,
                'duration': totalDuration,
              });
           }
           
           // Ordina i percorsi:
           analyzedRoutes.sort((a, b) {
             double maxA = a['maxRisk'] as double;
             double maxB = b['maxRisk'] as double;
             
             // 1. Priorità ASSOLUTA alla sicurezza (Rischio Massimo)
             // Se c'è una differenza anche minima di rischio, vince quello meno rischioso.
             // Nessuna tolleranza: Safety First.
             if ((maxA - maxB).abs() > 0.1) {
               return maxA.compareTo(maxB);
             }
             
             // 2. A parità di picco (es. entrambi 0% o entrambi 30%), 
             // vince quello con meno "quantità" di acqua totale.
             double totalA = a['totalRisk'] as double;
             double totalB = b['totalRisk'] as double;
             if ((totalA - totalB).abs() > 1.0) {
               return totalA.compareTo(totalB);
             }
             
             // 3. Se sicurezza è identica, vince il più breve (Durata in secondi)
             return (a['duration'] as int).compareTo(b['duration'] as int);
           });
           
           if (analyzedRoutes.isNotEmpty) {
             final best = analyzedRoutes.first;
             bestRoute = best['route'];
             bestRoutePoints = best['points'] as List<LatLng>;
           }
        } 
        
        // Default
        if (bestRoute == null) {
           bestRoute = routes[0];
           bestRoutePoints = _getDetailedPoints(bestRoute);
        }
        
        // Calcolo parametri display (uso i dati del 'bestRoute' che include somma legs)
        int totalSeconds = 0;
        int totalMeters = 0;
         if (bestRoute!['legs'] != null) {
            for(var leg in bestRoute!['legs']) {
                totalSeconds += (leg['duration']?['value'] ?? 0) as int;
                totalMeters += (leg['distance']?['value'] ?? 0) as int;
            }
         }
        
        int durationMinutes = (totalSeconds / 60).ceil();
        String distanceValue = totalMeters >= 1000 
            ? (totalMeters / 1000).toStringAsFixed(1) 
            : totalMeters.toString();
        String distanceUnit = totalMeters >= 1000 ? "km" : "m";

        List<LatLng> polylineCoordinates = bestRoutePoints!;

        // Polylines
        Set<Polyline> riskPolylines = {};
        if (_isRiskDataLoaded && _zones.isNotEmpty) {
          riskPolylines = _createRiskColoredPolylines(polylineCoordinates);
        } else {
          riskPolylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: polylineCoordinates,
            color: freshPrimary,
            width: 6,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ));
        }

        setState(() {
          _isRouteCalculated = true;
          _isCalculatingRoute = false;
          _routeDurationMinutes = durationMinutes;
          _routeDuration = durationMinutes > 0 ? durationMinutes.toString() : "--";
          _routeDistance = distanceValue;
          _routeDistanceUnit = distanceUnit;
          
          _polylines.addAll(riskPolylines);
        });
        
        // Feedback non intrusivo (SnackBar invece di Dialog)
        if (mounted && analyzedRoutes.isNotEmpty) {
            final best = analyzedRoutes.first;
            String msg = "Percorso aggiornato automaticamente.";
            
            if (best['maxRisk'] < 10) {
              msg = "✅ Trovato percorso sicuro (100% asciutto).";
            } else if (routes.length > 1) {
              msg = "⚠️ Percorso ottimizzato: scelto il meno rischioso disponibile.";
            }

            // Mostra SnackBar solo se necessario per confermare l'azione automatica
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(msg),
                backgroundColor: best['maxRisk'] < 20 ? Colors.green[700] : Colors.orange,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
         }
  }

  void _handleNetworkError(dynamic e) {
       // Fallback semplificato
       setState(() {
        _isRouteCalculated = true;
        _isCalculatingRoute = false;
        _routeDuration = "--";
        _routeDistance = "--";
       });
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Errore: $e")));
       }
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Helper per convertire la stringa durata in minuti
  int _parseDurationToMinutes(String duration) {
    int totalMinutes = 0;
    
    // Match ore
    final hoursMatch = RegExp(r'(\d+)\s*(?:hour|ora|ore|hr|h)').firstMatch(duration.toLowerCase());
    if (hoursMatch != null) {
      totalMinutes += int.parse(hoursMatch.group(1)!) * 60;
    }
    
    // Match minuti
    final minsMatch = RegExp(r'(\d+)\s*(?:min|minuti|minuto|m)').firstMatch(duration.toLowerCase());
    if (minsMatch != null) {
      totalMinutes += int.parse(minsMatch.group(1)!);
    }
    
    // Se non trova nulla, prova a estrarre solo numeri
    if (totalMinutes == 0) {
      final numMatch = RegExp(r'(\d+)').firstMatch(duration);
      if (numMatch != null) {
        totalMinutes = int.parse(numMatch.group(1)!);
      }
    }
    
    return totalMinutes;
  }

  // Helper per gestire errori API con fallback
  void _handleRouteError(String? status, String? errorMessage) {
    setState(() {
      _isRouteCalculated = false;
      _isCalculatingRoute = false;
      _routeDurationMinutes = 0;
      _routeDuration = "--";
      _routeDistance = "--";
      _routeDistanceUnit = "";
      _polylines.clear();
    });
    
    if (mounted) {
      _showRouteError(status, errorMessage);
    }
  }

  void _showRouteError(String? status, String? errorMessage) {
    String title = "Ops! Qualcosa non va";
    String description = "Non siamo riusciti a calcolare il percorso.";
    IconData icon = Icons.error_outline;
    Color color = Colors.red;

    switch (status) {
      case 'ZERO_RESULTS':
        title = "Nessun percorso trovato";
        description = "Sembra non ci siano strade percorribili a piedi tra questi due punti. Prova a selezionare punti più vicini alla terraferma o controlla se la destinazione è raggiungibile.";
        icon = Icons.wrong_location_outlined;
        color = Colors.orange;
        break;
      case 'REQUEST_DENIED':
        title = "Accesso Negato";
        description = "L'app non ha i permessi necessari. Verifica la configurazione dell'API Key di Google Maps.";
        icon = Icons.no_encryption_gmailerrorred_outlined;
        break;
      case 'OVER_QUERY_LIMIT':
        title = "Limite Raggiunto";
        description = "Abbiamo superato il numero di richieste consentite per oggi. Riprova più tardi.";
        break;
      case 'NOT_FOUND':
        title = "Luogo non trovato";
        description = "Uno dei punti selezionati non è valido. Prova a cercare un'altra posizione.";
        break;
      default:
        // Aggiungo dettaglio tecnico se disponibile
        if (errorMessage != null && errorMessage.isNotEmpty) {
           description += "\nDettaglio: $errorMessage";
        }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: const Text(
                  "Ho capito",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF),
      body: Stack(
        children: [
          // 1. Sfondo Mappa
          Positioned.fill(
            child: GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: _kVenice,
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              onMapCreated: _onMapCreated,
              markers: _markers,
              polylines: _polylines,
            ),
          ),

          // 2. Contenuto Principale
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Top Section: Search & Filters
                Padding(
                  padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
                  child: Column(
                    children: [
                      _buildSearchBar(),
                      const SizedBox(height: 16),
                      _buildFilterChips(),
                    ],
                  ),
                ),

                const Spacer(),

                // Pulsanti Fluttuanti a destra
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 24, bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _getUserLocation,
                          child: _buildCircleBtn(
                            _isLoadingLocation ? Icons.refresh : Icons.my_location,
                            isPrimary: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Section: Info Card e Nav Bar
                _buildBottomCard(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Widgets per la Top Section ---

  Widget _buildSearchBar() {
    final String? googleApiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Input Partenza
          Row(
            children: [
              const Icon(Icons.trip_origin, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "PARTENZA",
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    GooglePlaceAutoCompleteTextField(
                      textEditingController: _startSearchController,
                      googleAPIKey: googleApiKey ?? "",
                      inputDecoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: "Scegli punto di partenza...",
                      ),
                      textStyle: TextStyle(
                        color: freshText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      debounceTime: 400,
                      countries: const ["it"],
                      isLatLngRequired: true,
                      getPlaceDetailWithLatLng: (Prediction prediction) {
                        if (prediction.lat != null && prediction.lng != null) {
                          setState(() {
                            _startLocation = LatLng(
                              double.parse(prediction.lat!),
                              double.parse(prediction.lng!),
                            );
                            _startSearchController.text = prediction.description ?? "";
                          });
                          
                          _updateStartMarker();
                          
                          // Sposta camera
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLng(_startLocation!),
                          );
                        }
                      },
                      itemClick: (Prediction prediction) {
                        _startSearchController.text = prediction.description ?? "";
                        _startSearchController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _startSearchController.text.length),
                        );
                      },
                      seperatedBuilder: const Divider(),
                      containerHorizontalPadding: 10,
                      itemBuilder: (context, index, Prediction prediction) {
                        return Container(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.grey),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  prediction.description ?? "",
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      isCrossBtnShown: true,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _getUserLocation,
                child: _buildIconBtn(Icons.my_location, isFilled: true),
              ),
            ],
          ),
          
          const Divider(height: 24),

          // Input Destinazione
          Row(
            children: [
              Icon(Icons.location_on, color: freshMuted, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "DESTINAZIONE",
                      style: TextStyle(
                        color: freshPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    GooglePlaceAutoCompleteTextField(
                      textEditingController: _searchController,
                      googleAPIKey: googleApiKey ?? "",
                      inputDecoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        hintText: "Cerca un luogo...",
                      ),
                      textStyle: TextStyle(
                        color: freshText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      debounceTime: 400,
                      countries: const ["it"],
                      isLatLngRequired: true,
                      getPlaceDetailWithLatLng: (Prediction prediction) {
                        // Quando un luogo viene selezionato
                        if (prediction.lat != null && prediction.lng != null) {
                          setState(() {
                            _endLocation = LatLng(
                              double.parse(prediction.lat!),
                              double.parse(prediction.lng!),
                            );
                            _searchController.text = prediction.description ?? "";
                          });
                          
                          // Aggiungi marker destinazione
                          _markers.removeWhere((marker) => marker.markerId.value == 'end');
                          _markers.add(
                            Marker(
                              markerId: const MarkerId('end'),
                              position: _endLocation!,
                              infoWindow: InfoWindow(title: prediction.description),
                            ),
                          );
                          
                          // Sposta camera sulla destinazione
                          _mapController?.animateCamera(
                            CameraUpdate.newLatLng(_endLocation!),
                          );
                        }
                      },
                      itemClick: (Prediction prediction) {
                        _searchController.text = prediction.description ?? "";
                        _searchController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _searchController.text.length),
                        );
                      },
                      seperatedBuilder: const Divider(),
                      containerHorizontalPadding: 10,
                      itemBuilder: (context, index, Prediction prediction) {
                        return Container(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.grey),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  prediction.description ?? "",
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      isCrossBtnShown: true,
                    ),
                  ],
                ),
              ),
              _buildIconBtn(Icons.tune, isFilled: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconBtn(IconData icon, {bool isFilled = false}) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: isFilled ? const Color(0xFFF9FAFB) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: isFilled ? freshText : Colors.grey.shade400,
        size: 20,
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildLegendChip("Sicuro", Colors.green),
          const SizedBox(width: 8),
          _buildLegendChip("Attenzione", Colors.yellow[700]!),
          const SizedBox(width: 8),
          _buildLegendChip("Rischio", Colors.orange),
          const SizedBox(width: 8),
          _buildLegendChip("Pericolo", Colors.red),
        ],
      ),
    );
  }

  Widget _buildLegendChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 11,
              color: freshText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip({required String label, required Widget icon, bool isRichText = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          if (!isRichText)
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: freshText,
              ),
            )
          else
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'Manrope', // Se disponibile
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: freshText,
                ),
                children: const [
                  TextSpan(text: "Marea: "),
                  TextSpan(text: "Bassa", style: TextStyle(color: Colors.blue)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // --- Widgets Fluttuanti ---

  Widget _buildCircleBtn(IconData icon, {required bool isPrimary}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isPrimary ? Colors.blue : Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? Colors.blue.withOpacity(0.3)
                : Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: isPrimary ? Colors.white : Colors.grey.shade600,
        size: 24,
      ),
    );
  }

  // --- Card Inferiore (Route Details) ---

  Widget _buildBottomCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header: Tempo e Status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isRouteCalculated 
                            ? freshPrimary.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isRouteCalculated ? "CONSIGLIATO" : "SELEZIONA DESTINAZIONE",
                        style: TextStyle(
                          color: _isRouteCalculated ? freshPrimary : freshMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _isCalculatingRoute
                        ? Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: freshPrimary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                "Calcolo...",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: freshMuted,
                                ),
                              ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _routeDuration,
                                style: TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: _isRouteCalculated ? freshText : freshMuted,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "min",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  color: freshMuted,
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isRouteCalculated ? Icons.check_circle : Icons.circle_outlined,
                          color: _isRouteCalculated ? Colors.green : freshMuted,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isRouteCalculated ? "Percorso pronto" : "In attesa",
                          style: TextStyle(
                            color: _isRouteCalculated ? Colors.green.shade700 : freshMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isRouteCalculated 
                          ? "$_routeDistance$_routeDistanceUnit • A piedi"
                          : "-- • A piedi",
                      style: TextStyle(
                        color: freshMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Grid Stats
            Row(
              children: [
                _buildStatItem(
                  Icons.route,
                  _isRouteCalculated ? "$_routeDistance $_routeDistanceUnit" : "--",
                  Colors.blue.shade300,
                  label: "Distanza",
                ),
                const SizedBox(width: 12),
                _buildStatItem(
                  Icons.timer_outlined,
                  _isRouteCalculated ? "$_routeDuration min" : "--",
                  Colors.blue.shade300,
                  label: "Tempo",
                ),
                const SizedBox(width: 12),
                _buildStatItem(
                  Icons.directions_walk,
                  "A piedi",
                  Colors.blue.shade300,
                  label: "Modalità",
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Main Button
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 56,
              decoration: BoxDecoration(
                color: (_endLocation != null && !_isCalculatingRoute) 
                    ? Colors.blue 
                    : Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: (_endLocation != null && !_isCalculatingRoute)
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.transparent,
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: (_endLocation != null && !_isCalculatingRoute) 
                      ? _startNavigation 
                      : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24, right: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _isCalculatingRoute 
                              ? "Calcolo in corso..."
                              : _isRouteCalculated 
                                  ? "Avvia navigazione" 
                                  : "Calcola percorso",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _isCalculatingRoute
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  _isRouteCalculated 
                                      ? Icons.navigation 
                                      : Icons.arrow_forward,
                                  color: Colors.white,
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, Color iconColor, {String? label}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC), // gray-50
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: freshText,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (label != null) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: freshMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
