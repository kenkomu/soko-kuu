import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/ui/kit/kit.dart';
import 'package:soko_kuu/ui/theme.dart';

Widget host(Widget child, {double scale = 1, bool still = false}) =>
    MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(scale),
          disableAnimations: still,
        ),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  test('Money formatting', () {
    expect(formatPts(3800), '3,800 pts');
    expect(formatPts(0), '0 pts');
    expect(formatPts(-1250000), '-1,250,000 pts');
    expect(ksh(20000), 'Ksh 20,000.00');
    expect(ksh(1234.5), 'Ksh 1,234.50');
    expect(ksh(0.07), 'Ksh 0.07');
  });

  testWidgets('Money renders text with tabular figures', (t) async {
    await t.pumpWidget(host(const Money(3800)));
    final w = t.widget<Text>(find.text('3,800 pts'));
    expect(w.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('DeltaChip has arrow, sign and spoken label', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(
      host(
        const Column(children: [DeltaChip(120), DeltaChip(-45), DeltaChip(0)]),
      ),
    );
    expect(find.bySemanticsLabel('up +120'), findsOneWidget);
    expect(find.bySemanticsLabel('down -45'), findsOneWidget);
    expect(find.bySemanticsLabel('unchanged'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(find.text('+120'), findsOneWidget);
    h.dispose();
  });

  testWidgets(
    'RollingNumber shows final value at once with disableAnimations',
    (t) async {
      await t.pumpWidget(host(const RollingNumber(5000), still: true));
      expect(find.text('5,000'), findsOneWidget);
      await t.pumpWidget(host(const RollingNumber(9000), still: true));
      expect(find.text('9,000'), findsOneWidget);
    },
  );

  testWidgets('RollingNumber animates when allowed', (t) async {
    await t.pumpWidget(host(const RollingNumber(0)));
    await t.pumpWidget(host(const RollingNumber(1000)));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('1,000'), findsNothing);
    await t.pumpAndSettle();
    expect(find.text('1,000'), findsOneWidget);
  });

  testWidgets('SummaryStrip has no overflow at text scale 2.0', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      host(
        const SummaryStrip([
          SummaryCell(label: 'Balance', value: '1,234,500 pts'),
          SummaryCell(label: 'Owed', value: '20,000 pts'),
          SummaryCell(label: 'Saved this month', value: '3,800 pts'),
          SummaryCell(label: 'Group total', value: '9,999,999 pts'),
        ]),
        scale: 2.0,
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.text('Balance'), findsOneWidget);
  });

  testWidgets('Other kit widgets build at scale 2.0 without overflow', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      host(
        Column(
          children: [
            const StatusChip('Paid on time', tone: StatusTone.good),
            const StatusChip('Waiting for approval', tone: StatusTone.warn),
            const EmptyState('Nothing here yet.', title: 'Empty'),
            SokoCard(onTap: () {}, child: const Text('Tap me')),
            const KitengeBand(),
            const Sparkline([1, 3, 2, 5]),
            const Skeleton(width: 80),
          ],
        ),
        scale: 2.0,
        still: true,
      ),
    );
    expect(t.takeException(), isNull);
  });
}
