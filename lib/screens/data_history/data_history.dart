import 'dart:ui';
import 'package:flutter/material.dart';
import '../main_screen.dart'; // Import necessario per tornare alla Mappa

class DataHistoryScreen extends StatefulWidget {
  const DataHistoryScreen({super.key});

  @override
  State<DataHistoryScreen> createState() => _DataHistoryScreenState();
}

enum _Metric { tideLevel, airQuality, temperature }
enum _Range { h24, w1, m1 }

class _DataHistoryScreenState extends State<DataHistoryScreen> {
  // COLORI AGGIORNATI PER ALLINEARSI ALLE ALTRE PAGINE
  static const _primary = Color(0xFF3B82F6);
  static const _background = Color(0xFFEFF6FF); // Sfondo standard richiesto
  static const _textDark = Color(0xFF0F172A);

  static const _areas = <String>[
    'San Marco', 'Cannaregio', 'Dorsoduro', 'Castello', 'Giudecca'
  ];

  int _selectedAreaIndex = 0;
  _Metric _selectedMetric = _Metric.tideLevel;
  _Range _selectedRange = _Range.h24;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background, // Stesso sfondo delle altre schermate
      body: Stack(
        children: [
          // 1. CONTENUTO SCROLLABILE
          ListView(
            // Padding TOP aumentato a 120 per non finire sotto l'header
            padding: const EdgeInsets.fromLTRB(0, 120, 0, 96),
            children: [
              _SectionTitle(title: 'Seleziona Area', foregroundColor: _textDark),
              _AreaChips(
                areas: _areas,
                selectedIndex: _selectedAreaIndex,
                onSelect: (index) => setState(() => _selectedAreaIndex = index),
                primary: _primary,
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Seleziona Metrica', foregroundColor: _textDark),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _MetricGrid(
                  selected: _selectedMetric,
                  primary: _primary,
                  onSelect: (metric) => setState(() => _selectedMetric = metric),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _TrendCard(
                  primary: _primary,
                  range: _selectedRange,
                  onRangeChange: (range) => setState(() => _selectedRange = range),
                  valueText: '112',
                  unitText: 'cm',
                  deltaText: '+12%',
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _ExportButton(onPressed: () {}),
              ),
              const SizedBox(height: 24),
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
          padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 12, 16, 12),
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
              label: Text(areas[index], style: const TextStyle(fontWeight: FontWeight.w800)),
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
            child: Text(areas[index], style: const TextStyle(fontWeight: FontWeight.w600)),
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
    final titleColor = selected ? const Color(0xFF0F172A) : const Color(0xFF0F172A);
    final iconBg = selected ? primary.withOpacity(0.2) : const Color(0xFFF3F4F6);
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
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
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
  final String valueText;
  final String unitText;
  final String deltaText;

  const _TrendCard({
    required this.primary,
    required this.range,
    required this.onRangeChange,
    required this.valueText,
    required this.unitText,
    required this.deltaText,
  });

  @override
  Widget build(BuildContext context) {
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
                              'Trend Attuale'.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                                  valueText,
                                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: primary.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.trending_up, size: 14, color: primary),
                                      const SizedBox(width: 4),
                                      Text(
                                        deltaText,
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
                    child: CustomPaint(
                      painter: _TrendChartPainter(primary: primary),
                      child: const SizedBox.expand(),
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

class _RangePills extends StatelessWidget {
  final _Range range;
  final ValueChanged<_Range> onChange;
  final Color primary;

  const _RangePills({required this.range, required this.onChange, required this.primary});

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
      label: const Text('Esporta Report Dati', style: TextStyle(fontWeight: FontWeight.w800)),
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

class _TrendChartPainter extends CustomPainter {
  final Color primary;
  const _TrendChartPainter({required this.primary});
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()..color = Colors.white.withOpacity(0.10)..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);
    
    // Logica semplificata del grafico per la demo
    final path = Path();
    path.moveTo(0, size.height * 0.8);
    path.cubicTo(size.width * 0.2, size.height * 0.7, size.width * 0.5, size.height * 0.3, size.width, size.height * 0.2);
    
    final linePaint = Paint()
      ..color = primary
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
    
    // Sfumatura sotto
    final areaPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final gradient = LinearGradient(
      colors: [primary.withOpacity(0.3), primary.withOpacity(0.0)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    canvas.drawPath(areaPath, Paint()..shader = gradient.createShader(Offset.zero & size));
  }
  @override
  bool shouldRepaint(covariant _TrendChartPainter old) => old.primary != primary;
}