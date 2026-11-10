import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../l10n.dart';
import '../state/providers.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  tr('Start playing'),
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Play now as a guest. Add an email later to save progress on another device or join a chama.',
                  ),
                ),
                const SizedBox(height: 16),
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
                            final s = await loadSigner(ref.read(prefsProvider));
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
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () => _run(() async {
                          final s = await loadSigner(ref.read(prefsProvider));
                          await ref.read(apiProvider).guest(s.pubkey);
                          ref.read(loggedInProvider.notifier).done();
                        }),
                  child: Text(tr('Play as a guest (no email)')),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(demoModeProvider.notifier).set(true),
                  child: Text(tr('Play the offline demo instead')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
