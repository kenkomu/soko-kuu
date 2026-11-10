import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soko_kuu/l10n.dart';

void main() {
  test('ARB error sentences match errorText for en and sw', () {
    for (final lang in ['en', 'sw']) {
      final arb =
          jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map;
      for (final e in errorText.entries) {
        expect(arb['error_${e.key}'], e.value[lang], reason: '${e.key}/$lang');
      }
    }
  });
}
