import 'package:flutter/material.dart';

/// Plain-wording snackbar. Always icon + text, so colour is never the only cue.
/// Pass an already translated, one-sentence [msg].
void toast(BuildContext context, String msg, {bool error = false}) {
  final s = Theme.of(context).colorScheme;
  final bg = error ? s.errorContainer : s.secondaryContainer;
  final fg = error ? s.onErrorContainer : s.onSecondaryContainer;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(msg, style: TextStyle(color: fg)),
            ),
          ],
        ),
      ),
    );
}
