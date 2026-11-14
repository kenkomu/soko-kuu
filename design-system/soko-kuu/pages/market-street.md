# Market Street (Soko Run top strip): art direction

Overrides MASTER.md for the animated market scene only. The trading UI below it keeps MASTER rules.

## What it is
A short, wide diorama strip at the top of the Soko Run screen: three stalls (Njeri: tomato, Wanjiru: maize, Baraka: sukuma),
a radio on a pole, and the player's trader who walks to a stall when it is tapped. Built in Blender, shipped as small
pre-rendered images (background plate + per-stall layers + character sprite sheets). No real-time 3D in the app.

## Look: "soft clay diorama"
- Chunky, rounded, toy-like forms; bevelled edges; no sharp detail that dies at phone size.
- A floating slab of market ground (like a model-village base) on the cream app background, soft contact shadow underneath.
- Warm key light from upper left, cool soft fill; gentle ambient occlusion. Picture-book warmth, not photoreal.
- Materials: matte clay for people and produce, corrugated mabati roofs (painted: terracotta, indigo, teal), wooden tables,
  kitenge-pattern awnings using the brand zig-zag.
- Palette: brand colours only, plus produce colours (tomato red, maize gold, sukuma green). Dawn: warm peach; midday: neutral;
  dusk: amber with lamps on (5 lighting states = 5 days).

## Character
- Proportions: big head, short body (about 2.5 heads tall) so it reads at 64-96 px tall.
- A young Kenyan trader: kitenge top, carrying a gunia (sack) that visibly fills (3 sack sizes).
- Respectful, not a caricature. Varied skin tones across NPC passers-by. Review with Kenyan players before release.
- Animations: idle (8 frames), walk left/right (12 frames), "buy" bounce (6 frames). 3/4 side view only.

## Technical budget
- Strip height 160-200 dp; render at 3x for sharpness, ship WebP.
- Target: background plate <= 60 KB, each character sheet <= 40 KB, total scene <= 250 KB.
- Walk to a stall <= 0.8 s, tappable to skip. Reduced-motion: no walking, character appears at the stall.
- Everything decorative must be excluded from semantics; the stall tap targets carry the labels ("Njeri's tomato stall").

## Motion and feedback (from MASTER: 150-300 ms UI transitions; game motion may be longer)
- Price spike: stall bounces once and the crowd grows; glut: produce pile grows; drought: warm dusty tint; rain: light rain layer.
- Never more than one effect at a time on the strip.
