import 'package:flutter/material.dart';

import 'money.dart';

bool reduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Counts from its previous value to [value]. Shows the final value at once
/// when the platform asks for reduced motion.
class RollingNumber extends StatelessWidget {
  const RollingNumber(
    this.value, {
    super.key,
    this.format,
    this.style,
    this.textAlign,
    this.duration = const Duration(milliseconds: 600),
  });

  final int value;

  /// Defaults to [fmt] (thousands separators). Use `(n) => '${fmt(n)} pts'`.
  final String Function(int)? format;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final f = format ?? fmt;
    final st = (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (reduceMotion(context)) {
      return Text(f(value), style: st, textAlign: textAlign);
    }
    return Semantics(
      label: f(value),
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: value.toDouble()),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (_, v, _) =>
            Text(f(v.round()), style: st, textAlign: textAlign),
      ),
    );
  }
}

/// Scales its child to ~0.96 while pressed. Guarantees a 48dp tap area.
class PressSquish extends StatefulWidget {
  const PressSquish({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final double scale;

  @override
  State<PressSquish> createState() => _PressSquishState();
}

class _PressSquishState extends State<PressSquish> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final still = reduceMotion(context);
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: widget.semanticLabel,
      container: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: enabled ? (_) => _set(false) : null,
        onTapCancel: enabled ? () => _set(false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: AnimatedScale(
            scale: _down && !still ? widget.scale : 1,
            duration: still ? Duration.zero : const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Pulsing placeholder block (opacity only, no shimmer sweep).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 8});
  final double? width;
  final double height, radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _running = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = reduceMotion(context);
    if (still && _running) {
      _c.stop();
      _running = false;
    } else if (!still && !_running) {
      _c.repeat(reverse: true);
      _running = true;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base.withValues(alpha: .07 + .07 * _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}
