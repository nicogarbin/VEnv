import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class DataHistoryScreen extends StatefulWidget {
	const DataHistoryScreen({super.key});

	@override
	State<DataHistoryScreen> createState() => _DataHistoryScreenState();
}

enum _Metric {
	tideLevel,
	airQuality,
	temperature,
}

enum _Range {
	h24,
	w1,
	m1,
}

class _DataHistoryScreenState extends State<DataHistoryScreen> {
	static const _primary = Color(0xFF3B82F6);
	static const _backgroundLight = Color(0xFFEFF6FF);
	static const _backgroundDark = Color(0xFF0F172A);
	static const _surfaceDark = Color(0xFF1E293B);
	static const _surfaceLight = Color(0xFFFFFFFF);

	static const _areas = <String>[
		'San Marco',
		'Cannaregio',
		'Dorsoduro',
		'Castello',
		'Giudecca',
	];

	int _selectedAreaIndex = 0;
	_Metric _selectedMetric = _Metric.tideLevel;
	_Range _selectedRange = _Range.h24;

	bool get _isDark {
		final brightness = Theme.of(context).brightness;
		return brightness == Brightness.dark;
	}

	Color get _pageBackground => _isDark ? _backgroundDark : _backgroundLight;

	Color get _pageForeground => _isDark ? Colors.white : const Color(0xFF0F172A);

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			backgroundColor: _pageBackground,
			body: Stack(
				children: [
					Positioned.fill(
						child: IgnorePointer(
							child: Opacity(
								opacity: 0.03,
								child: Image.network(
									'https://lh3.googleusercontent.com/aida-public/AB6AXuAKz2GXeTw_01Xo2jmAjLkbR0Zu-OADhzfohg9nnxUHNxCER6ULR6vOjOsPNG7NGIlX_cSZSR0jtiUnHZ8SWW_gzCi1fCddTnMKFk1qqPQSRvhiq7AkS4jqYdPjuVJJsivjmp8anDQaUZJrs5U-79vGZiiMQbRbppwwrcPTIH5_Dz5Vz9DqlzDGrB9AzGhXDk0cDBMzc90Eghf2ju3Yy5LDMJ4_YZrGggbBWUfnvHbL7iObPFywsLPLMiHgGqmiBgVqiBZcMunIoh3S',
									fit: BoxFit.cover,
									errorBuilder: (context, error, stackTrace) {
										return const SizedBox.shrink();
									},
								),
							),
						),
					),
					SafeArea(
						bottom: false,
						child: Center(
							child: ConstrainedBox(
								constraints: const BoxConstraints(maxWidth: 420),
								child: Material(
									color: _pageBackground,
									elevation: 12,
									child: Column(
										children: [
											_StickyHeader(
												backgroundColor: _pageBackground,
												foregroundColor: _pageForeground,
												onBack: () => Navigator.of(context).maybePop(),
											),
											Expanded(
												child: ListView(
													padding: const EdgeInsets.only(bottom: 96),
													children: [
														const SizedBox(height: 8),
														_SectionTitle(
															title: 'Select Areas',
															foregroundColor: _pageForeground,
														),
														_AreaChips(
															areas: _areas,
															selectedIndex: _selectedAreaIndex,
															onSelect: (index) {
																setState(() => _selectedAreaIndex = index);
															},
															isDark: _isDark,
															primary: _primary,
														),
														const SizedBox(height: 16),
														_SectionTitle(
															title: 'Select Metric',
															foregroundColor: _pageForeground,
														),
														Padding(
															padding: const EdgeInsets.symmetric(horizontal: 24),
															child: _MetricGrid(
																selected: _selectedMetric,
																primary: _primary,
																isDark: _isDark,
																onSelect: (metric) {
																	setState(() => _selectedMetric = metric);
																},
															),
														),
														const SizedBox(height: 16),
														Padding(
															padding: const EdgeInsets.symmetric(horizontal: 24),
															child: _TrendCard(
																primary: _primary,
																range: _selectedRange,
																onRangeChange: (range) {
																	setState(() => _selectedRange = range);
																},
																valueText: '112',
																unitText: 'cm',
																deltaText: '+12%',
															),
														),
														const SizedBox(height: 16),
														Padding(
															padding: const EdgeInsets.symmetric(horizontal: 24),
															child: _ExportButton(
																isDark: _isDark,
																onPressed: () {
																	// Template button: no extra behavior required.
																},
															),
														),
														const SizedBox(height: 24),
													],
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
		);
	}
}

class _StickyHeader extends StatelessWidget {
	final Color backgroundColor;
	final Color foregroundColor;
	final VoidCallback onBack;

	const _StickyHeader({
		required this.backgroundColor,
		required this.foregroundColor,
		required this.onBack,
	});

	@override
	Widget build(BuildContext context) {
		return ClipRect(
			child: BackdropFilter(
				filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
				child: Container(
					padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
					decoration: BoxDecoration(
						color: backgroundColor.withOpacity(0.9),
					),
					child: Row(
						children: [
							IconButton(
								onPressed: onBack,
								icon: Icon(Icons.arrow_back, color: foregroundColor),
								style: IconButton.styleFrom(
									backgroundColor: Colors.transparent,
									shape: const CircleBorder(),
								),
							),
							Expanded(
								child: Text(
									'Historical Trends',
									textAlign: TextAlign.center,
									style: Theme.of(context).textTheme.titleMedium?.copyWith(
												fontWeight: FontWeight.w800,
												color: foregroundColor,
											),
								),
							),
							const SizedBox(width: 48),
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

	const _SectionTitle({
		required this.title,
		required this.foregroundColor,
	});

	@override
	Widget build(BuildContext context) {
		return Padding(
			padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
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
	final bool isDark;
	final Color primary;

	const _AreaChips({
		required this.areas,
		required this.selectedIndex,
		required this.onSelect,
		required this.isDark,
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

					final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
					final fillColor = isDark ? const Color(0xFF1E293B) : Colors.white;
					final textColor = isDark ? const Color(0xFFD1D5DB) : const Color(0xFF0F172A);
					return OutlinedButton(
						onPressed: () => onSelect(index),
						style: OutlinedButton.styleFrom(
							backgroundColor: fillColor,
							foregroundColor: textColor,
							padding: const EdgeInsets.symmetric(horizontal: 18),
							shape: const StadiumBorder(),
							side: BorderSide(color: borderColor),
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
	final bool isDark;
	final ValueChanged<_Metric> onSelect;

	const _MetricGrid({
		required this.selected,
		required this.primary,
		required this.isDark,
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
					isDark: isDark,
					icon: Icons.water_drop_outlined,
					title: 'Tide Level',
					onTap: () => onSelect(_Metric.tideLevel),
				),
				_MetricTile(
					selected: selected == _Metric.airQuality,
					primary: primary,
					isDark: isDark,
					icon: Icons.air,
					title: 'Air Quality',
					onTap: () => onSelect(_Metric.airQuality),
				),
				_MetricTile(
					selected: selected == _Metric.temperature,
					primary: primary,
					isDark: isDark,
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
	final bool isDark;
	final IconData icon;
	final String title;
	final VoidCallback onTap;

	const _MetricTile({
		required this.selected,
		required this.primary,
		required this.isDark,
		required this.icon,
		required this.title,
		required this.onTap,
	});

	@override
	Widget build(BuildContext context) {
		final borderColor = selected
				? primary
				: (isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB));
		final surface = isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);
		final titleColor = selected
				? (isDark ? Colors.white : const Color(0xFF0F172A))
				: (isDark ? const Color(0xFFD1D5DB) : const Color(0xFF0F172A));

		final iconBg = selected
				? primary.withOpacity(0.2)
				: (isDark ? const Color(0xFF111827) : const Color(0xFFF3F4F6));
		final iconColor = selected ? primary : (isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280));

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
						border: Border.all(
							color: borderColor,
							width: selected ? 2 : 1,
						),
						boxShadow: selected
								? [
										BoxShadow(
											color: primary.withOpacity(0.15),
											blurRadius: 12,
											offset: const Offset(0, 6),
										),
									]
								: null,
					),
					child: Stack(
						children: [
							Column(
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
							if (selected)
								Positioned(
									top: 0,
									right: 0,
									child: Container(
										padding: const EdgeInsets.all(2),
										decoration: BoxDecoration(
											color: primary,
											shape: BoxShape.circle,
										),
										child: const Icon(Icons.check, size: 14, color: Colors.white),
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
				color: const Color(0xFF1E293B),
				child: Stack(
					children: [
						Positioned.fill(
							child: Opacity(
								opacity: 0.10,
								child: CustomPaint(
									painter: _DotGridPainter(dotColor: primary),
								),
							),
						),
						Padding(
							padding: const EdgeInsets.all(20),
							child: Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									Row(
										crossAxisAlignment: CrossAxisAlignment.start,
										children: [
											Expanded(
												child: Column(
													crossAxisAlignment: CrossAxisAlignment.start,
													children: [
														Text(
															'Current Trend'.toUpperCase(),
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
																		style: Theme.of(context).textTheme.titleSmall?.copyWith(
																					color: const Color(0xFF9CA3AF),
																					fontWeight: FontWeight.w700,
																				),
																	),
																),
																const SizedBox(width: 10),
																Padding(
																	padding: const EdgeInsets.only(bottom: 8),
																	child: Container(
																		padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
																		decoration: BoxDecoration(
																			color: primary.withOpacity(0.2),
																			borderRadius: BorderRadius.circular(999),
																		),
																		child: Row(
																			mainAxisSize: MainAxisSize.min,
																			children: [
																				Icon(Icons.trending_up, size: 14, color: primary),
																				const SizedBox(width: 4),
																				Text(
																					deltaText,
																					style: Theme.of(context).textTheme.labelSmall?.copyWith(
																								color: primary,
																								fontWeight: FontWeight.w800,
																							),
																				),
																			],
																		),
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
										child: Column(
											children: [
												Expanded(
													child: CustomPaint(
														painter: _TrendChartPainter(primary: primary),
														child: const SizedBox.expand(),
													),
												),
												const SizedBox(height: 8),
												const Row(
													mainAxisAlignment: MainAxisAlignment.spaceBetween,
													children: [
														Text('12 AM', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
														Text('6 AM', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
														Text('12 PM', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
														Text('6 PM', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
														Text('Now', style: TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
													],
												),
											],
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
						style: Theme.of(context).textTheme.labelSmall?.copyWith(
									color: selected ? Colors.white : const Color(0xFF9CA3AF),
									fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
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
	final bool isDark;
	final VoidCallback onPressed;

	const _ExportButton({
		required this.isDark,
		required this.onPressed,
	});

	@override
	Widget build(BuildContext context) {
		final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
		final background = isDark ? const Color(0xFF1E293B) : Colors.white;
		final foreground = isDark ? Colors.white : const Color(0xFF0F172A);

		return OutlinedButton.icon(
			onPressed: onPressed,
			style: OutlinedButton.styleFrom(
				backgroundColor: background,
				foregroundColor: foreground,
				side: BorderSide(color: borderColor),
				padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
				shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
			),
			icon: const Icon(Icons.download),
			label: const Text(
				'Export Data Report',
				style: TextStyle(fontWeight: FontWeight.w800),
			),
		);
	}
}

class _DotGridPainter extends CustomPainter {
	final Color dotColor;

	const _DotGridPainter({required this.dotColor});

	@override
	void paint(Canvas canvas, Size size) {
		final paint = Paint()..color = dotColor;
		const spacing = 16.0;
		const radius = 1.0;

		for (double y = 0; y < size.height; y += spacing) {
			for (double x = 0; x < size.width; x += spacing) {
				canvas.drawCircle(Offset(x, y), radius, paint);
			}
		}
	}

	@override
	bool shouldRepaint(covariant _DotGridPainter oldDelegate) {
		return oldDelegate.dotColor != dotColor;
	}
}

class _TrendChartPainter extends CustomPainter {
	final Color primary;

	const _TrendChartPainter({required this.primary});

	@override
	void paint(Canvas canvas, Size size) {
		final gridPaint = Paint()
			..color = Colors.white.withOpacity(0.10)
			..strokeWidth = 1;

		// Baseline (y=150 in template)
		canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), gridPaint);
		_drawDashedLine(
			canvas,
			from: Offset(0, size.height * (2 / 3)),
			to: Offset(size.width, size.height * (2 / 3)),
			paint: gridPaint,
			dash: 4,
			gap: 4,
		);
		_drawDashedLine(
			canvas,
			from: Offset(0, size.height * (1 / 3)),
			to: Offset(size.width, size.height * (1 / 3)),
			paint: gridPaint,
			dash: 4,
			gap: 4,
		);

		// Points approximating the SVG path (normalized into current size).
		// SVG viewBox: 300x150
		Offset p(double x, double y) {
			return Offset(x / 300 * size.width, y / 150 * size.height);
		}

		final points = <Offset>[
			p(0, 120),
			p(40, 110),
			p(80, 60),
			p(120, 70),
			p(160, 80),
			p(200, 40),
			p(240, 50),
			p(280, 60),
			p(300, 30),
		];

		final linePath = _smoothPath(points);
		final areaPath = Path.from(linePath)
			..lineTo(size.width, size.height)
			..lineTo(0, size.height)
			..close();

		final gradient = LinearGradient(
			begin: Alignment.topCenter,
			end: Alignment.bottomCenter,
			colors: [
				primary.withOpacity(0.30),
				primary.withOpacity(0.0),
			],
		);

		final areaPaint = Paint()
			..shader = gradient.createShader(Offset.zero & size)
			..style = PaintingStyle.fill;
		canvas.drawPath(areaPath, areaPaint);

		final linePaint = Paint()
			..color = primary
			..strokeWidth = 3
			..style = PaintingStyle.stroke
			..strokeCap = StrokeCap.round
			..strokeJoin = StrokeJoin.round;
		canvas.drawPath(linePath, linePaint);

		// Highlight point around x=240,y=50.
		final highlight = p(240, 50);
		final dotFill = Paint()..color = primary;
		final dotStroke = Paint()
			..color = Colors.white.withOpacity(0.8)
			..style = PaintingStyle.stroke
			..strokeWidth = 3;
		canvas.drawCircle(highlight, 5, dotFill);
		canvas.drawCircle(highlight, 5, dotStroke);

		// Tooltip.
		_drawTooltip(canvas, anchor: highlight, text: '112cm');
	}

	Path _smoothPath(List<Offset> pts) {
		if (pts.length < 2) return Path();
		final path = Path()..moveTo(pts[0].dx, pts[0].dy);
		for (int i = 0; i < pts.length - 1; i++) {
			final p0 = pts[i];
			final p1 = pts[i + 1];
			final control = Offset((p0.dx + p1.dx) / 2, p0.dy);
			final control2 = Offset((p0.dx + p1.dx) / 2, p1.dy);
			path.cubicTo(control.dx, control.dy, control2.dx, control2.dy, p1.dx, p1.dy);
		}
		return path;
	}

	void _drawDashedLine(
		Canvas canvas, {
		required Offset from,
		required Offset to,
		required Paint paint,
		required double dash,
		required double gap,
	}) {
		final total = (to - from).distance;
		if (total <= 0) return;
		final direction = (to - from) / total;
		double drawn = 0;
		while (drawn < total) {
			final start = from + direction * drawn;
			final end = from + direction * math.min(drawn + dash, total);
			canvas.drawLine(start, end, paint);
			drawn += dash + gap;
		}
	}

	void _drawTooltip(Canvas canvas, {required Offset anchor, required String text}) {
		final textPainter = TextPainter(
			text: TextSpan(
				text: text,
				style: const TextStyle(
					fontSize: 10,
					fontWeight: FontWeight.w800,
					color: Colors.black,
				),
			),
			textDirection: TextDirection.ltr,
		)..layout();

		const tooltipW = 50.0;
		const tooltipH = 24.0;
		final rect = RRect.fromRectAndRadius(
			Rect.fromCenter(
				center: Offset(anchor.dx, anchor.dy - 28),
				width: tooltipW,
				height: tooltipH,
			),
			const Radius.circular(6),
		);

		final paint = Paint()..color = Colors.white;
		canvas.drawRRect(rect, paint);

		final textOffset = Offset(
			rect.center.dx - textPainter.width / 2,
			rect.center.dy - textPainter.height / 2,
		);
		textPainter.paint(canvas, textOffset);

		final triangle = Path()
			..moveTo(rect.center.dx - 4, rect.bottom)
			..lineTo(rect.center.dx + 4, rect.bottom)
			..lineTo(rect.center.dx, rect.bottom + 6)
			..close();
		canvas.drawPath(triangle, paint);
	}

	@override
	bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
		return oldDelegate.primary != primary;
	}
}

