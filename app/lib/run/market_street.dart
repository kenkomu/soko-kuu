import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n.dart';
import '../ui/kit/motion.dart';
import '../ui/theme.dart';
import 'run_widgets.dart';

/// Market street strip at the top of the Soko Run screen. Off by default;
/// build with `--dart-define=SOKO_MARKET_STREET=true` to turn it on.
const bool kMarketStreet = bool.fromEnvironment('SOKO_MARKET_STREET');

/// Whether the Soko Run screen shows the market street. Tests override it.
final marketStreetProvider = Provider<bool>((ref) => kMarketStreet);

const kStreetPlate = 'assets/street/plate.webp';
const kStreetWalk = 'assets/street/walk.webp';

/// Longest walk between two stalls, in milliseconds. The controller ends on
/// the frame after this, so the trader always arrives within 0.8 s.
const kStreetWalkMs = 750;

// Geometry of the v2 Blender render (market_v2.blend, plate_geometry.json),
// re-expressed for plate.webp, which is v2_plate.png cropped to its visible
// pixels (x 22..1378, y 70..606 of 1400x636). All values are fractions of the
// plate's width and height, projected from the scene's camera, so the sprite
// stands on the same ground line and at the same scale as the stall owners.
const _plateAspect = 1356 / 536;
const _pathY = .7449; // feet line of the walking path
const _startX = .3877; // where the trader stands when the run starts
const _frames = 12; // walk cycle, facing right
const _frameAspect = 84 / 141; // one frame of walk.webp
const _spriteH = .2423; // frame height / plate height (character: .2320)
const _feetX = .5536, _feetY = .9814; // feet inside a frame
const _frameMs = 33; // about 30 frames a second while walking
const _longestWalk = .7950 - .2050; // Njeri to Baraka

class StreetStall {
  const StreetStall(this.good, this.owner, this.x);
  final String good;
  final String owner;

  /// Centre of the stall (and where the trader stops), as a width fraction.
  final double x;

  String get label => tr('{n}\'s {g} stall', {
    'n': owner,
    'g': runGoodName(good).toLowerCase(),
  });
}

const streetStalls = [
  StreetStall('tomato', 'Njeri', .2050),
  StreetStall('maize', 'Wanjiru', .5),
  StreetStall('sukuma', 'Baraka', .7950),
];

/// The street: a pre-rendered plate, three tappable stalls and the player's
/// trader. Tapping a stall walks the trader there (at most [kStreetWalkMs];
/// tap again to skip) and then calls [onArrive] with that stall's good.
/// With reduced motion the trader appears at the stall at once.
/// The plate and the trader are decorative and hidden from screen readers;
/// each stall is one labelled button.
class MarketStreet extends StatefulWidget {
  const MarketStreet({super.key, required this.onArrive});

  final void Function(String good) onArrive;

  @override
  State<MarketStreet> createState() => _MarketStreetState();
}

class _MarketStreetState extends State<MarketStreet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _walk = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _arrive();
    });
  double _x = _startX, _from = _startX, _to = _startX;
  String? _target, _focus;
  bool _left = false;

  @override
  void dispose() {
    _walk.dispose();
    super.dispose();
  }

  double get _now => _target == null
      ? _x
      : _from + (_to - _from) * Curves.easeInOut.transform(_walk.value);

  void _tap(StreetStall s) {
    if (_target == s.good) return _skip();
    final here = _now;
    _walk.stop();
    final d = (s.x - here).abs();
    if (reduceMotion(context) || d < .005) {
      setState(() {
        _x = s.x;
        _target = null;
      });
      widget.onArrive(s.good);
      return;
    }
    final ms = (kStreetWalkMs * d / _longestWalk).clamp(240, kStreetWalkMs);
    setState(() {
      _from = here;
      _to = s.x;
      _left = s.x < here;
      _target = s.good;
    });
    _walk
      ..duration = Duration(milliseconds: ms.round())
      ..forward(from: 0);
  }

  void _skip() {
    if (_target == null) return;
    _walk.stop();
    _arrive();
  }

  void _arrive() {
    final good = _target;
    if (good == null) return;
    setState(() {
      _x = _to;
      _target = null;
    });
    widget.onArrive(good);
  }

  @override
  Widget build(BuildContext context) {
    final gold = context.tokens.ochre;
    return AspectRatio(
      key: const Key('street'),
      aspectRatio: _plateAspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth, h = box.maxHeight;
          final fh = _spriteH * h, fw = fh * _frameAspect;
          return RepaintBoundary(
            child: GestureDetector(
              // A tap anywhere on the street finishes a walk early.
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _skip,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(
                    child: ExcludeSemantics(
                      child: Image(
                        image: AssetImage(kStreetPlate),
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  for (final s in streetStalls)
                    Positioned(
                      left: (s.x - .11) * w,
                      width: .22 * w,
                      top: .18 * h,
                      height: .76 * h,
                      child: Semantics(
                        button: true,
                        label: s.label,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            key: Key('stall-${s.good}'),
                            customBorder: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            splashColor: gold.withValues(alpha: .22),
                            highlightColor: Colors.transparent,
                            hoverColor: gold.withValues(alpha: .12),
                            focusColor: gold.withValues(alpha: .12),
                            onFocusChange: (f) => setState(
                              () => _focus = f
                                  ? s.good
                                  : (_focus == s.good ? null : _focus),
                            ),
                            onTap: () => _tap(s),
                            // Keyboard focus: a solid gold ring, not only a tint.
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: _focus == s.good
                                    ? Border.all(color: gold, width: 3)
                                    : null,
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  AnimatedBuilder(
                    animation: _walk,
                    builder: (context, _) {
                      final x = _now;
                      final walking = _target != null;
                      final ms =
                          (_walk.value * (_walk.duration?.inMilliseconds ?? 0))
                              .round();
                      final frame = walking ? (ms ~/ _frameMs) % _frames : 0;
                      return Positioned(
                        key: const Key('street-walker'),
                        left: x * w - _feetX * fw,
                        top: _pathY * h - _feetY * fh,
                        width: fw,
                        height: fh,
                        child: RepaintBoundary(
                          child: IgnorePointer(
                            child: ExcludeSemantics(
                              child: _Walker(frame: frame, left: _left),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One frame of the walk sheet with a soft contact shadow. Facing left is the
/// right-facing frame mirrored.
class _Walker extends StatelessWidget {
  const _Walker({required this.frame, required this.left});
  final int frame;
  final bool left;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final fw = box.maxWidth, fh = box.maxHeight;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _feetX * fw - fw * .38,
              top: _feetY * fh - fh * .05,
              width: fw * .76,
              height: fh * .09,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(
                    Radius.elliptical(fw * .38, fh * .045),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 6),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Transform.flip(
                flipX: left,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: fw * _frames,
                    maxWidth: fw * _frames,
                    minHeight: fh,
                    maxHeight: fh,
                    child: Transform.translate(
                      offset: Offset(-frame * fw, 0),
                      child: const Image(
                        image: AssetImage(kStreetWalk),
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A short gold ring around a good's row after the trader reaches its stall,
/// so the eye lands on the Buy and Sell buttons. Bump [pulse] to replay it.
class StallSpotlight extends StatefulWidget {
  const StallSpotlight({super.key, required this.pulse, required this.child});

  /// 0 shows nothing; each new value plays the ring once.
  final int pulse;
  final Widget child;

  @override
  State<StallSpotlight> createState() => _StallSpotlightState();
}

class _StallSpotlightState extends State<StallSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse != 0) _c.forward();
  }

  @override
  void didUpdateWidget(StallSpotlight old) {
    super.didUpdateWidget(old);
    if (widget.pulse != old.pulse && widget.pulse != 0) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _c.value;
        // In fast, hold, out slowly; nothing once done.
        final a = !_c.isAnimating
            ? 0.0
            : v < .1
            ? v / .1
            : v < .6
            ? 1.0
            : (1 - v) / .4;
        if (a <= 0) return child!;
        return DecoratedBox(
          key: const Key('stall-spotlight'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.ochre.withValues(alpha: a), width: 3),
          ),
          child: child,
        );
      },
    );
  }
}
