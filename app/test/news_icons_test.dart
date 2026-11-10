import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/l10n.dart';
import 'package:soko_kuu/ui/widgets.dart';

void main() {
  const kinds = ['ukame', 'fuel', 'road', 'festival', 'harvest', 'glut'];

  test(
    'every news kind has a Swahili headline; unknown kind keeps English',
    () {
      for (final k in kinds) {
        expect(newsSwKind.containsKey(k), isTrue, reason: k);
        expect(newsText(k, 'Some new text', 'sw'), newsSwKind[k]);
        expect(newsText(k, 'Some new text', 'en'), 'Some new text');
      }
      expect(newsText('mystery', 'Plain English', 'sw'), 'Plain English');
    },
  );

  test('known demo bulletins are translated in full', () {
    for (final e in newsSwExact.entries) {
      expect(newsText('harvest', e.key, 'sw'), e.value);
      expect(newsText('harvest', e.key, 'en'), e.key);
    }
  });

  test('every good has a bundled icon, not an emoji', () {
    for (final g in [
      'tomato',
      'kale',
      'sukuma',
      'maize',
      'onion',
      'beans',
      'fish',
      'charcoal',
    ]) {
      expect(goodIcons.containsKey(g), isTrue, reason: g);
    }
  });

  testWidgets('GoodIcon renders an Icon with no Text', (t) async {
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: GoodIcon('tomato'))),
    );
    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });
}
