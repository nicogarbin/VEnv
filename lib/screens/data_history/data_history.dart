import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../main_screen.dart'; // Import necessario per tornare alla Mappa

class DataHistoryScreen extends StatefulWidget {
  const DataHistoryScreen({super.key});

  @override
  State<DataHistoryScreen> createState() => _DataHistoryScreenState();
}

enum _Metric { tideLevel, airQuality, temperature }

enum _Range { h24, w1, m1 }

class _SeriesPoint {
  final DateTime time;
  final double value;

  const _SeriesPoint({required this.time, required this.value});
}

class _MetricSpec {
  final String collection;
  final String valueField;
  final String timeField;
  final String? areaField;
  final String title;
  final String unit;
  final bool isTideMeters;

  const _MetricSpec({
    required this.collection,
    required this.valueField,
    required this.timeField,
    required this.title,
    required this.unit,
    this.areaField,
    this.isTideMeters = false,
  });

  static _MetricSpec fromMetric(_Metric metric) {
    switch (metric) {
      case _Metric.tideLevel:
        return const _MetricSpec(
          collection: 'Maree',
          valueField: 'altezza',
          timeField: 'data',
          areaField: 'zona',
          title: 'Marea',
          unit: 'cm',
          isTideMeters: true,
        );
      case _Metric.airQuality:
        return const _MetricSpec(
          collection: "Qualita dell'aria",
          valueField: 'valore',
          timeField: 'data',
          title: 'Qualità Aria',
          unit: 'AQI',
        );
      case _Metric.temperature:
        return const _MetricSpec(
          collection: 'Temperatura',
          valueField: 'valore',
          timeField: 'data',
          title: 'Temperatura',
          unit: '°C',
        );
    }
  }
}

class _DataHistoryScreenState extends State<DataHistoryScreen> {
  // COLORI AGGIORNATI PER ALLINEARSI ALLE ALTRE PAGINE
  static const _primary = Color(0xFF3B82F6);
  static const _background = Color(0xFFEFF6FF); // Sfondo standard richiesto
  static const _textDark = Color(0xFF0F172A);

  static const _tideStations = <String>[
    'Punta Salute Canal Grande',
    'Punta Salute Canale Giudecca',
    'Venezia Misericordia',
    'S. Geremia',
    'Giudecca',
    'Burano',
    'Fusina',
    'Laguna nord Saline',
    'Malamocco Porto',
    'Diga sud Lido',
    'Diga nord Malamocco',
    'Diga sud Chioggia',
    'Chioggia Vigo',
    'Chioggia porto',
    'Piattaforma Acqua Alta Siap',
  ];

  static const _genericAreas = <String>['Venezia'];

  int _selectedAreaIndex = 0;
  _Metric _selectedMetric = _Metric.tideLevel;
  _Range _selectedRange = _Range.h24;

  static Duration _durationForRange(_Range range) {
    switch (range) {
      case _Range.h24:
        return const Duration(hours: 24);
      case _Range.w1:
        return const Duration(days: 7);
      case _Range.m1:
        return const Duration(days: 30);
    }
  }

  /// Normalizza stringhe data provenienti da Firestore, coprendo:
  /// - "YYYY-MM-DD HH:mm:ss"  -> "YYYY-MM-DDTHH:mm:ss"
  /// - ISO con frazione secondi con lunghezza variabile -> microsecondi (6 cifre)
  static String _normalizeDateString(String raw) {
    var s = raw.trim();

    // "2026-01-22 00:05:00" -> "2026-01-22T00:05:00"
    if (s.contains(' ') && !s.contains('T')) {
      s = s.replaceFirst(' ', 'T');
    }

    // Normalizza la parte frazionaria dei secondi (microsecondi).
    // Dart gestisce bene fino a 6 cifre: .SSSSSS
    final match = RegExp(r'^(.*\d{2}:\d{2}:\d{2})(\.(\d+))?$').firstMatch(s);
    if (match != null) {
      final base = match.group(1)!;
      final frac = match.group(3); // solo cifre
      if (frac == null) return base;

      if (frac.length == 6) return '$base.$frac';
      if (frac.length > 6) return '$base.${frac.substring(0, 6)}';
      // se meno di 6, pad a destra
      return '$base.${frac.padRight(6, '0')}';
    }

    return s;
  }

  static DateTime? _parseFirestoreDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String) {
      final normalized = _normalizeDateString(raw);
      return DateTime.tryParse(normalized);
    }
    return null;
  }

  /// Carica le zone realmente presenti nella collezione "Maree".
  /// Firestore non ha "distinct", quindi estraiamo le zone dagli ultimi N documenti.
  Stream<List<String>> _watchTideAreas() {
    return FirebaseFirestore.instance
        .collection('Maree')
        .orderBy('data', descending: true)
        .limit(2000)
        .snapshots()
        .map((snapshot) {
          final set = <String>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final z = data['zona'];
            if (z is String) {
              final trimmed = z.trim();
              if (trimmed.isNotEmpty) set.add(trimmed);
            }
          }
          final list = set.toList()..sort();
          return list.isEmpty ? _tideStations : list;
        });
  }

  Stream<
    ({
      List<_SeriesPoint> points,
      int docsCount,
      int validCount,
      DateTime? latest,
      DateTime? oldest,
    })
  > _watchSeries({required String selectedArea}) {
    final spec = _MetricSpec.fromMetric(_selectedMetric);
    final cutoff = DateTime.now().subtract(_durationForRange(_selectedRange));

    Query<Map<String, dynamic>> query;

    if (spec.areaField != null && _selectedMetric == _Metric.tideLevel) {
      // Per avere un grafico corretto serve ordine per "data".
      // Questo richiede indice composito: (zona ASC) + (data DESC) sulla collezione "Maree".
      query = FirebaseFirestore.instance
          .collection(spec.collection)
          .where(spec.areaField!, isEqualTo: selectedArea)
          .orderBy(spec.timeField, descending: true)
          .limit(3000);
    } else {
      // Per aria/temperatura: nessun filtro, orderBy sicuro.
      query = FirebaseFirestore.instance
          .collection(spec.collection)
          .orderBy(spec.timeField, descending: true)
          .limit(1000);
    }

    return query.snapshots().map((snapshot) {
      final points = <_SeriesPoint>[];
      DateTime? latest;
      DateTime? oldest;
      var validCount = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final dt = _parseFirestoreDate(data[spec.timeField]);
        if (dt == null) continue;

        final rawValue = data[spec.valueField];
        if (rawValue is! num) continue;

        validCount += 1;
        if (latest == null || dt.isAfter(latest)) latest = dt;
        if (oldest == null || dt.isBefore(oldest)) oldest = dt;

        if (dt.isBefore(cutoff)) continue;

        double value = rawValue.toDouble();
        if (spec.isTideMeters) {
          // In functions/main.py: altezza è in metri -> convertiamo in cm.
          value = value * 100.0;
        }

        points.add(_SeriesPoint(time: dt, value: value));
      }

      // Ordina lato client (anche se la query è già in desc, qui vogliamo asc per il grafico)
      points.sort((a, b) => a.time.compareTo(b.time));

      // Downsample leggero per UI fluida (max ~160 punti)
      const maxPoints = 160;
      List<_SeriesPoint> displayPoints;
      if (points.length <= maxPoints) {
        displayPoints = points;
      } else {
        final step = (points.length / maxPoints).ceil();
        final sampled = <_SeriesPoint>[];
        for (int i = 0; i < points.length; i += step) {
          sampled.add(points[i]);
        }
        displayPoints = sampled;
      }

      return (
        points: displayPoints,
        docsCount: snapshot.docs.length,
        validCount: validCount,
        latest: latest,
        oldest: oldest,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final metricSpec = _MetricSpec.fromMetric(_selectedMetric);

    // Altezza header: 12(top) + 48(row) + 12(bottom) + status bar/notch.
    const headerBaseHeight = 108.0;
    final listTopPadding =
        MediaQuery.of(context).padding.top + headerBaseHeight + 24;

    final areasStream = _selectedMetric == _Metric.tideLevel
        ? _watchTideAreas()
        : Stream.value(_genericAreas);

    return Scaffold(
      backgroundColor: _background, // Stesso sfondo delle altre schermate
      body: Stack(
        children: [
          // 1. CONTENUTO SCROLLABILE
          ListView(
            // Padding TOP dinamico per non finire sotto l'header (anche con notch).
            padding: EdgeInsets.fromLTRB(0, listTopPadding, 0, 96),
            children: [
              StreamBuilder<List<String>>(
                stream: areasStream,
                builder: (context, areasSnap) {
                  final areas = areasSnap.data ??
                      (_selectedMetric == _Metric.tideLevel
                          ? _tideStations
                          : _genericAreas);

                  final safeIndex = areas.isEmpty
                      ? 0
                      : _selectedAreaIndex.clamp(0, areas.length - 1);

                  if (areas.isNotEmpty && safeIndex != _selectedAreaIndex) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() => _selectedAreaIndex = safeIndex);
                    });
                  }

                  final selectedArea =
                      areas.isEmpty ? 'Venezia' : areas[safeIndex];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionTitle(
                        title: _selectedMetric == _Metric.tideLevel
                            ? 'Seleziona Stazione'
                            : 'Area',
                        foregroundColor: _textDark,
                      ),
                      _AreaChips(
                        areas: areas,
                        selectedIndex: safeIndex,
                        onSelect: (index) =>
                            setState(() => _selectedAreaIndex = index),
                        primary: _primary,
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(
                        title: 'Seleziona Metrica',
                        foregroundColor: _textDark,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _MetricGrid(
                          selected: _selectedMetric,
                          primary: _primary,
                          onSelect: (metric) {
                            setState(() {
                              _selectedMetric = metric;
                              _selectedAreaIndex = 0;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: StreamBuilder<
                            ({
                              List<_SeriesPoint> points,
                              int docsCount,
                              int validCount,
                              DateTime? latest,
                              DateTime? oldest,
                            })>(
                          stream: _watchSeries(selectedArea: selectedArea),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              final details = snapshot.error.toString();
                              final friendly = details
                                      .toLowerCase()
                                      .contains('requires an index')
                                  ? 'Manca un indice Firestore per la query Maree.\n'
                                      'Crea un indice composito su:\n'
                                      '- Collection: Maree\n'
                                      '- Fields: zona (ASC), data (DESC)\n\n'
                                      'Dettagli:\n$details'
                                  : 'Errore Firebase:\n$details';

                              return _TrendCard(
                                primary: _primary,
                                range: _selectedRange,
                                onRangeChange: (range) =>
                                    setState(() => _selectedRange = range),
                                title: metricSpec.title,
                                unitText: metricSpec.unit,
                                points: const [],
                                errorText: friendly,
                              );
                            }

                            if (!snapshot.hasData) {
                              return _TrendCard(
                                primary: _primary,
                                range: _selectedRange,
                                onRangeChange: (range) =>
                                    setState(() => _selectedRange = range),
                                title: metricSpec.title,
                                unitText: metricSpec.unit,
                                points: const [],
                                isLoading: true,
                              );
                            }

                            final series = snapshot.data!;
                            String? emptyText;
                            if (series.points.isEmpty) {
                              if (series.validCount > 0 &&
                                  series.latest != null) {
                                emptyText =
                                    'Nessun dato nel range selezionato\n'
                                    'Ultimo dato: ${DateFormat('dd/MM/yyyy HH:mm').format(series.latest!)}\n'
                                    'Prova ad allargare il range';
                              } else if (series.docsCount > 0 &&
                                  series.validCount == 0) {
                                emptyText =
                                    'Dati trovati ma non leggibili\n'
                                    'Controlla i campi "${metricSpec.timeField}" e "${metricSpec.valueField}"';
                              }
                            }

                            return _TrendCard(
                              primary: _primary,
                              range: _selectedRange,
                              onRangeChange: (range) =>
                                  setState(() => _selectedRange = range),
                              title: metricSpec.title,
                              unitText: metricSpec.unit,
                              points: series.points,
                              emptyText: emptyText,
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: _ExportButton(onPressed: () {}),
                      ),
                      const SizedBox(height: 24),
                    ],
                  );
                },
              ),
            ],
          ),

          // 2. HEADER FISSO (Identico alle altre pagine)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _StickyHeader(
              title: 'Storico Dati',
              onBack: () {
                // Torna alla schermata principale (Mappa)
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const MainScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- CLASSI DI SUPPORTO ---

// HEADER AGGIORNATO (Stile coerente)
class _StickyHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _StickyHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            16,
            MediaQuery.of(context).padding.top + 12,
            16,
            12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF).withOpacity(0.9),
            border: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.5),
                  shape: const CircleBorder(),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(width: 48), // Bilanciamento visivo
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color foregroundColor;

  const _SectionTitle({required this.title, required this.foregroundColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class _AreaChips extends StatelessWidget {
  final List<String> areas;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Color primary;

  const _AreaChips({
    required this.areas,
    required this.selectedIndex,
    required this.onSelect,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: areas.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          if (selected) {
            return FilledButton.tonalIcon(
              onPressed: () => onSelect(index),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.check, size: 18),
              label: Text(
                areas[index],
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            );
          }
          return OutlinedButton(
            onPressed: () => onSelect(index),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            child: Text(
              areas[index],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final _Metric selected;
  final Color primary;
  final ValueChanged<_Metric> onSelect;

  const _MetricGrid({
    required this.selected,
    required this.primary,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      primary: false,
      padding: EdgeInsets.zero,
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1,
      children: [
        _MetricTile(
          selected: selected == _Metric.tideLevel,
          primary: primary,
          icon: Icons.water_drop_outlined,
          title: 'Marea',
          onTap: () => onSelect(_Metric.tideLevel),
        ),
        _MetricTile(
          selected: selected == _Metric.airQuality,
          primary: primary,
          icon: Icons.air,
          title: 'Qualità Aria',
          onTap: () => onSelect(_Metric.airQuality),
        ),
        _MetricTile(
          selected: selected == _Metric.temperature,
          primary: primary,
          icon: Icons.thermostat,
          title: 'Temp',
          onTap: () => onSelect(_Metric.temperature),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final bool selected;
  final Color primary;
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _MetricTile({
    required this.selected,
    required this.primary,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? primary : const Color(0xFFE5E7EB);
    final surface = Colors.white;
    final titleColor = selected
        ? const Color(0xFF0F172A)
        : const Color(0xFF0F172A);
    final iconBg = selected
        ? primary.withOpacity(0.2)
        : const Color(0xFFF3F4F6);
    final iconColor = selected ? primary : const Color(0xFF6B7280);

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: titleColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  final Color primary;
  final _Range range;
  final ValueChanged<_Range> onRangeChange;
  final String title;
  final String unitText;
  final List<_SeriesPoint> points;
  final bool isLoading;
  final String? errorText;
  final String? emptyText;

  const _TrendCard({
    required this.primary,
    required this.range,
    required this.onRangeChange,
    required this.unitText,
    required this.title,
    required this.points,
    this.isLoading = false,
    this.errorText,
    this.emptyText,
  });

  String _formatValue(double v) {
    // Evita .0 inutili
    if (v.abs() >= 100) return v.toStringAsFixed(0);
    if (v.abs() >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  ({String valueText, String deltaText}) _computeHeadline() {
    if (points.isEmpty) return (valueText: '--', deltaText: '--');
    final last = points.last.value;
    String delta;
    if (points.length < 2) {
      delta = '--';
    } else {
      final first = points.first.value;
      if (first == 0) {
        delta = '--';
      } else {
        final pct = ((last - first) / first) * 100.0;
        final sign = pct >= 0 ? '+' : '';
        delta = '$sign${pct.toStringAsFixed(1)}%';
      }
    }
    return (valueText: _formatValue(last), deltaText: delta);
  }

  @override
  Widget build(BuildContext context) {
    final headline = _computeHeadline();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: const Color(0xFF1E293B), // Card scura per contrasto grafico
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.10,
                child: CustomPaint(painter: _DotGridPainter(dotColor: primary)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: const Color(0xFF9CA3AF),
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  headline.valueText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displaySmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        height: 1,
                                      ),
                                ),
                                const SizedBox(width: 6),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(
                                    unitText,
                                    style: const TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        headline.deltaText.startsWith('-')
                                            ? Icons.trending_down
                                            : Icons.trending_up,
                                        size: 14,
                                        color: primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        headline.deltaText,
                                        style: TextStyle(
                                          color: primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _RangePills(
                        range: range,
                        onChange: onRangeChange,
                        primary: primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 208,
                    child: _TrendChart(
                      primary: primary,
                      range: range,
                      points: points,
                      isLoading: isLoading,
                      errorText: errorText,
                      emptyText: emptyText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final Color primary;
  final _Range range;
  final List<_SeriesPoint> points;
  final bool isLoading;
  final String? errorText;
  final String? emptyText;

  const _TrendChart({
    required this.primary,
    required this.range,
    required this.points,
    required this.isLoading,
    required this.errorText,
    this.emptyText,
  });

  String _formatBottom(DateTime dt) {
    switch (range) {
      case _Range.h24:
        return DateFormat('HH:mm').format(dt);
      case _Range.w1:
        return DateFormat('E').format(dt); // lun, mar, ... (locale)
      case _Range.m1:
        return DateFormat('d/M').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (errorText != null) {
      return Center(
        child: Text(
          errorText!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (points.isEmpty) {
      final text = emptyText ?? 'Nessun dato nel range selezionato';
      return Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final spots = points
        .map((p) => FlSpot(p.time.millisecondsSinceEpoch.toDouble(), p.value))
        .toList(growable: false);

    double minY = points.first.value;
    double maxY = points.first.value;
    for (final p in points) {
      if (p.value < minY) minY = p.value;
      if (p.value > maxY) maxY = p.value;
    }
    final pad = (maxY - minY).abs() * 0.15;
    final paddedMinY = minY - (pad == 0 ? 1 : pad);
    final paddedMaxY = maxY + (pad == 0 ? 1 : pad);

    final minX = spots.first.x;
    final maxX = spots.last.x;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: paddedMinY,
        maxY: paddedMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (paddedMaxY - paddedMinY) / 4,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.white.withOpacity(0.10), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: (paddedMaxY - paddedMinY) / 4,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (maxX - minX) / 3,
              getTitlesWidget: (value, meta) {
                final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _formatBottom(dt),
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [primary.withOpacity(0.30), primary.withOpacity(0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.black.withOpacity(0.75),
            getTooltipItems: (touchedSpots) {
              return touchedSpots
                  .map((barSpot) {
                    final dt = DateTime.fromMillisecondsSinceEpoch(
                      barSpot.x.toInt(),
                    );
                    final label =
                        '${DateFormat('dd/MM HH:mm').format(dt)}\n${barSpot.y.toStringAsFixed(2)}';
                    return LineTooltipItem(
                      label,
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    );
                  })
                  .toList(growable: false);
            },
          ),
        ),
      ),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }
}

class _RangePills extends StatelessWidget {
  final _Range range;
  final ValueChanged<_Range> onChange;
  final Color primary;

  const _RangePills({
    required this.range,
    required this.onChange,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill({required String text, required _Range value}) {
      final selected = value == range;
      return InkWell(
        onTap: () => onChange(value),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF9CA3AF),
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill(text: '24H', value: _Range.h24),
          pill(text: '1W', value: _Range.w1),
          pill(text: '1M', value: _Range.m1),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ExportButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const Icon(Icons.download),
      label: const Text(
        'Esporta Report Dati',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

// Custom Painters rimasti invariati per la grafica del grafico
class _DotGridPainter extends CustomPainter {
  final Color dotColor;
  const _DotGridPainter({required this.dotColor});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor;
    const spacing = 16.0;
    for (double y = 0; y < size.height; y += spacing) {
      for (double x = 0; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter old) => old.dotColor != dotColor;
}
