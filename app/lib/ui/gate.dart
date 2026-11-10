import 'package:flutter/material.dart';

import '../l10n.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'widgets.dart';

class AgeGate18 extends ConsumerWidget {
  const AgeGate18({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const KitengeBand(height: 14),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Soko Kuu',
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('Karibu sokoni. A market-trading game.'),
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('Before you start'),
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  tr(
                                    '• This game is for people aged 18 and over.',
                                  ),
                                ),
                                Text(
                                  tr(
                                    '• You play with pointi (pts). Pts are only for play: they cannot be bought, sent, or cashed out.',
                                  ),
                                ),
                                Text(
                                  tr(
                                    '• There are no prizes and no paid chances. Prices follow fixed market rules.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () =>
                                ref.read(ageGateProvider.notifier).accept(),
                            child: Text(tr('I am 18 or older. Start')),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text(tr('Sorry')),
                                content: Text(
                                  tr(
                                    'Soko Kuu is for players aged 18 and over. Please come back when you are older.',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            ),
                            child: Text(tr('I am under 18')),
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
}
