import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../l10n.dart';
import '../run/entry.dart';
import '../state/providers.dart';
import 'gate.dart' show IntroDots;
import 'widgets.dart';

/// Email magic-link login (real mode only). Two steps: send link, paste code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final email = TextEditingController(), code = TextEditingController();
  bool consent = false, sent = false, busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) {
        toast(context, friendlyError(e, ref.read(langProvider)), error: true);
      }
    }
    if (mounted) setState(() => busy = false);
  }

  int step = 1; // 0 = age gate, 1 = how it works, 2 = start

  Future<void> _guest() => _run(() async {
    final s = await loadSigner(ref.read(prefsProvider));
    await ref.read(apiProvider).guest(s.pubkey);
    ref.read(loggedInProvider.notifier).done();
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    Expanded(child: IntroDots(step: step)),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: busy
                          ? null
                          : () =>
                                step == 1 ? setState(() => step = 2) : _guest(),
                      child: Text(_bi('Skip', 'Ruka')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (step == 1) ...[
                  Text(
                    _bi('How Soko Kuu works', 'Soko Kuu inavyofanya kazi'),
                    style: tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Point(
                    Icons.storefront_outlined,
                    _bi(
                      'Buy goods at dawn and midday, sell at dusk.',
                      'Nunua bidhaa asubuhi na adhuhuri, uza jioni.',
                    ),
                  ),
                  _Point(
                    Icons.groups_outlined,
                    _bi(
                      'Join a chama to pool pts with friends.',
                      'Jiunge na chama kuchanganya pointi na marafiki.',
                    ),
                  ),
                  _Point(
                    Icons.info_outline,
                    tr('Points are for play only. They can\'t be cashed out.'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(() => step = 2),
                    child: Text(_bi('Next', 'Endelea')),
                  ),
                ] else ...[
                  Text(
                    tr('Start playing'),
                    style: tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr(
                      'Play now as a guest. Add an email later to save progress on another device or join a chama.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : _guest,
                    child: Text(tr('Play as a guest (no email)')),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _bi(
                      'Want to save your progress? Optional.',
                      'Unataka kuhifadhi maendeleo yako? Si lazima.',
                    ),
                    style: tt.titleSmall,
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: consent,
                    onChanged: (v) => setState(() => consent = v ?? false),
                    title: Text(
                      tr(
                        'I agree to be emailed a sign-in link and to keep my email on file for this account.',
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: busy || !consent || email.text.trim().isEmpty
                        ? null
                        : () => _run(() async {
                            final s = await loadSigner(ref.read(prefsProvider));
                            await ref
                                .read(apiProvider)
                                .register(email.text.trim(), s.pubkey);
                            setState(() => sent = true);
                          }),
                    child: Text(sent ? 'Send again' : 'Email me a link'),
                  ),
                  if (sent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: code,
                      decoration: InputDecoration(
                        labelText: tr('Code from the link'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              final s = await loadSigner(
                                ref.read(prefsProvider),
                              );
                              await ref
                                  .read(apiProvider)
                                  .confirm(code.text.trim(), s.pubkey);
                              await ref
                                  .read(prefsProvider)
                                  .setBool('email_bound', true);
                              ref.read(loggedInProvider.notifier).done();
                            }),
                      child: Text(tr('Confirm')),
                    ),
                  ],
                  TextButton(
                    onPressed: () =>
                        ref.read(demoModeProvider.notifier).set(true),
                    child: Text(tr('Play the offline demo instead')),
                  ),
                ],
                TextButton(
                  onPressed: () =>
                      ref.read(entryProvider.notifier).set(Entry.run),
                  child: Text(tr('Back to Soko Run')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _bi(String en, String sw) => gLang == 'sw' ? sw : en;

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// Guests must add an email before joining or starting a chama.
/// Returns true when an email is already bound (or demo mode, which needs none).
Future<bool> ensureEmail(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  if (ref.read(demoModeProvider) || (prefs.getBool('email_bound') ?? false)) {
    return true;
  }
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _EmailSheet(),
  );
  return ok ?? false;
}

class _EmailSheet extends ConsumerStatefulWidget {
  const _EmailSheet();
  @override
  ConsumerState<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends ConsumerState<_EmailSheet> {
  final email = TextEditingController(), code = TextEditingController();
  bool consent = false, sent = false, busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => busy = true);
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) {
        toast(context, friendlyError(e, ref.read(langProvider)), error: true);
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      0,
      16,
      16 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Add your email to join a chama'),
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Chama members need a saved account so the group can trust each other. We email a sign-in link.',
            ),
          ),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consent,
            onChanged: (v) => setState(() => consent = v ?? false),
            title: Text(
              tr(
                'I agree to be emailed a sign-in link and to keep my email on file for this account.',
              ),
            ),
          ),
          FilledButton(
            onPressed: busy || !consent || email.text.trim().isEmpty
                ? null
                : () => _run(() async {
                    final s = await loadSigner(ref.read(prefsProvider));
                    await ref
                        .read(apiProvider)
                        .register(email.text.trim(), s.pubkey);
                    setState(() => sent = true);
                  }),
            child: Text(sent ? 'Send again' : 'Email me a link'),
          ),
          if (sent) ...[
            TextField(
              controller: code,
              decoration: InputDecoration(labelText: tr('Code from the link')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => _run(() async {
                      final s = await loadSigner(ref.read(prefsProvider));
                      await ref
                          .read(apiProvider)
                          .confirm(code.text.trim(), s.pubkey);
                      await ref
                          .read(prefsProvider)
                          .setBool('email_bound', true);
                      if (context.mounted) Navigator.pop(context, true);
                    }),
              child: Text(tr('Confirm')),
            ),
          ],
        ],
      ),
    ),
  );
}
