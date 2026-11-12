import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n.dart';
import '../state/providers.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Which part of the app opens after the 18+ gate: the choice, Soko Run, or
/// the live market (the existing guest and sign-in flow). Saved in prefs.
enum Entry { ask, run, live }

class EntryNotifier extends Notifier<Entry> {
  @override
  Entry build() => switch (ref.read(prefsProvider).getString('entry')) {
    'run' => Entry.run,
    'live' => Entry.live,
    _ => Entry.ask,
  };

  void set(Entry e) {
    state = e;
    ref.read(prefsProvider).setString('entry', e.name);
  }
}

final entryProvider = NotifierProvider<EntryNotifier, Entry>(EntryNotifier.new);

/// Shown once after the 18+ gate: Soko Run first, the live market second.
class EntryChoice extends ConsumerWidget {
  const EntryChoice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final muted = tt.bodyMedium?.copyWith(color: context.tokens.muted);
    void go(Entry e) => ref.read(entryProvider.notifier).set(e);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const KitengeBand(height: 14),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Soko Kuu',
                          style: tt.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('How do you want to play?'),
                          style: tt.titleLarge,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(48, 56),
                            textStyle: tt.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          icon: const Icon(Icons.storefront),
                          onPressed: () => go(Entry.run),
                          label: Text(tr('Play Soko Run')),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            'Ten quick market days on this phone. No sign-in, nothing is sent anywhere.',
                          ),
                          style: muted,
                        ),
                        const SizedBox(height: 20),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 52),
                            foregroundColor: cs.tertiary,
                            side: BorderSide(color: cs.tertiary, width: 2),
                          ),
                          icon: const Icon(Icons.groups_outlined),
                          onPressed: () => go(Entry.live),
                          label: Text(tr('Live market on NEAR')),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(
                            'The shared market with chama, credit and other players.',
                          ),
                          style: muted,
                        ),
                        const SizedBox(height: 20),
                        Text(tr('You can switch later.'), style: muted),
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
}
