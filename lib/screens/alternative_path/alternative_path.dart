import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';

class AlternativePath extends StatefulWidget {
  const AlternativePath({super.key});

  @override
  State<AlternativePath> createState() => _AlternativePathState();
}

class _AlternativePathState extends State<AlternativePath> {
  // Palette colori definita dall'HTML
  final Color freshPrimary = const Color(0xFF00B4D8);
  final Color freshText = const Color(0xFF334155);
  final Color freshMuted = const Color(0xFF94A3B8);

  // Map State
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _searchController = TextEditingController(text: "Ponte di Rialto");

  static const CameraPosition _kVenice = CameraPosition(
    target: LatLng(45.4408, 12.3155),
    zoom: 14.0,
  );

  // Coordinate simulate
  final LatLng _startLocation = const LatLng(45.4408, 12.3155); // Unive
  final LatLng _endLocation = const LatLng(45.4381, 12.3359); // Rialto

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  Future<void> _startNavigation() async {
    // 1. Setup Markers
    setState(() {
      _markers.clear();
      _polylines.clear();
      
      _markers.add(
        Marker(
          markerId: const MarkerId('start'),
          position: _startLocation,
          infoWindow: const InfoWindow(title: 'Partenza'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('end'),
          position: _endLocation,
          infoWindow: const InfoWindow(title: 'Destinazione'),
        ),
      );
    });

    // 2. Fetch Route from Google Directions API
    const String googleApiKey = "AIzaSyBEXuj3n-Jf13SGSb7P6tpw1LBNNmjFPOQ"; 
    
    PolylinePoints polylinePoints = PolylinePoints(apiKey: googleApiKey);
    PolylineResult result = await polylinePoints.getRouteBetweenCoordinates(
      request: PolylineRequest(
        origin: PointLatLng(_startLocation.latitude, _startLocation.longitude),
        destination: PointLatLng(_endLocation.latitude, _endLocation.longitude),
        mode: TravelMode.walking,
      ),
    );

    if (result.status == 'OK' && result.points.isNotEmpty) {
      List<LatLng> polylineCoordinates = result.points
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();

      setState(() {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: polylineCoordinates,
            color: freshPrimary,
            width: 5,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      });
    } else {
       // Fallback: Linea retta se API fallisce o manca Key
       setState(() {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route_fallback'),
            points: [_startLocation, _endLocation],
            color: freshPrimary.withOpacity(0.5),
            width: 5,
            patterns: [PatternItem.dash(10), PatternItem.gap(10)],
          ),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Impossibile caricare percorso reale: ${result.errorMessage ?? 'Verifica API Key'}")),
        );
      }
    }

    // 3. Move Camera
    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(
        _startLocation.latitude < _endLocation.latitude ? _startLocation.latitude : _endLocation.latitude,
        _startLocation.longitude < _endLocation.longitude ? _startLocation.longitude : _endLocation.longitude,
      ),
      northeast: LatLng(
        _startLocation.latitude > _endLocation.latitude ? _startLocation.latitude : _endLocation.latitude,
        _startLocation.longitude > _endLocation.longitude ? _startLocation.longitude : _endLocation.longitude,
      ),
    );
    
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Sfondo Mappa
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kVenice,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            onMapCreated: _onMapCreated,
            markers: _markers,
            polylines: _polylines,
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
                        _buildCircleBtn(Icons.layers_outlined, isPrimary: false),
                        const SizedBox(height: 12),
                        _buildCircleBtn(Icons.my_location, isPrimary: true),
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
      // --- Bottom Nav Bar Placeholder ---
      bottomNavigationBar: _buildCustomNavBar(),
    );
  }

  // --- Widgets per la Top Section ---

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(Icons.search, color: freshMuted),
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
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  onSubmitted: (value) {
                    // Simula ricerca
                    _startNavigation();
                  },
                ),
              ],
            ),
          ),
          _buildIconBtn(Icons.mic_none),
          _buildIconBtn(Icons.tune, isFilled: true),
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
    return Row(
      children: [
        _buildChip(
          label: "Percorso Sicuro",
          icon: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: freshPrimary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildChip(
          label: "Marea: Bassa",
          icon: const Icon(Icons.water_drop, color: Colors.blueAccent, size: 16),
          isRichText: true,
        ),
      ],
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
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 4),
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
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Color(0xFF4B5563),
              ),
            )
          else
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontFamily: 'Manrope', // Se disponibile
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Color(0xFF4B5563),
                ),
                children: [
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
        color: isPrimary ? freshText : Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: isPrimary
                ? Colors.black.withOpacity(0.2)
                : Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
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
              color: freshPrimary.withOpacity(0.3),
              blurRadius: 40,
              offset: const Offset(0, 10),
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
                        color: freshPrimary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "CONSIGLIATO",
                        style: TextStyle(
                          color: freshPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "12",
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: freshText,
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
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          "Asciutto",
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "850m • A piedi",
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
                _buildStatItem(Icons.water_drop, "0%", Colors.blue.shade300),
                const SizedBox(width: 12),
                _buildStatItem(Icons.groups, "Bassa", Colors.orange.shade300),
                const SizedBox(width: 12),
                _buildStatItem(Icons.stairs, "4", Colors.purple.shade300),
              ],
            ),
            const SizedBox(height: 24),
            // Main Button
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: freshPrimary,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.cyan.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _startNavigation,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 24, right: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Avvia percorso",
                          style: TextStyle(
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
                          child: const Icon(Icons.arrow_forward, color: Colors.white),
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

  Widget _buildStatItem(IconData icon, String value, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Bottom Nav Bar Placeholder ---
  Widget _buildCustomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40), // Reduced horizontal padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavItem(Icons.map, "Mappa"),
          _buildNavItem(Icons.history, "Storico"),
          _buildNavItem(Icons.alt_route, "Percorso", isSelected: true),
          _buildNavItem(Icons.article, "News"),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, {bool isSelected = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 28, // Increased icon size
          color: isSelected ? freshPrimary : freshMuted,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? freshPrimary : freshMuted,
          ),
        ),
      ],
    );
  }
}

