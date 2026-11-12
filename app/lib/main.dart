import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'run/entry.dart';
import 'run/soko_run_screen.dart';
import 'state/providers.dart';
import 'ui/gate.dart';
import 'ui/home.dart';
import 'ui/kit/feel.dart';
import 'ui/login.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  Feel.load(prefs);
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const SokoKuuApp(),
    ),
  );
}

class SokoKuuApp extends ConsumerWidget {
  const SokoKuuApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ok = ref.watch(ageGateProvider);
    return MaterialApp(
      title: 'Soko Kuu',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      key: ValueKey(ref.watch(langProvider)),
      locale: Locale(ref.watch(langProvider)),
      supportedLocales: supportedLangs,
      localizationsDelegates: localeDelegates,
      home: !ok
          ? const AgeGate18()
          : switch (ref.watch(entryProvider)) {
              Entry.ask => const EntryChoice(),
              Entry.run => const SokoRunScreen(),
              Entry.live =>
                ref.watch(loggedInProvider)
                    ? const HomeShell()
                    : const LoginScreen(),
            },
    );
  }
}
