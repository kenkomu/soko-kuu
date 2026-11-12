# Soko Kuu UI kit

`import '../widgets.dart';` (re-exports `kit/kit.dart`) or `import 'kit/kit.dart';`.
Colours: `context.tokens` (SokoTokens: up, down, ochre, indigo, onIndigo, teal, muted, card, kitenge[4]); `Theme.of(context).colorScheme` for the rest. Fonts: Fredoka (headings, money) and DMSans (body), bundled. Ochre is a fill, never text.
Kit widgets take already-translated strings: pass `tr('...')`.

- `fmt(int)` -> "3,800"; `formatPts(int, {unit='pts'})` -> "3,800 pts"; `ksh(num)` -> "Ksh 20,000.00".
- `Money(int pts, {style, textAlign, unit='pts', showUnit=true})`: `Money(3800, textAlign: TextAlign.end)`
- `DeltaChip(int delta, {suffix='', upWord='up', downWord='down', flatWord='unchanged'})`: `DeltaChip(120, upWord: tr('up'), downWord: tr('down'), flatWord: tr('unchanged'))`
- `RollingNumber(int value, {format, style, textAlign, duration})`: `RollingNumber(bal, format: formatPts, style: tt.headlineMedium)`; shows final value at once if animations are disabled.
- `PressSquish({child, onTap, onLongPress, semanticLabel, scale=0.96})`: `PressSquish(onTap: go, semanticLabel: tr('Open'), child: tile)`; min 48x48.
- `Sparkline(List<num> values, {width=64, height=28, color, semanticLabel})`: `Sparkline([10, 12, 9, 15])`
- `KitengeBand({height=10, radius=0})`: headers and empty states only; decorative.
- `SokoCard({child, padding=16, onTap, color, semanticLabel})`: `SokoCard(onTap: open, child: Text(...))`
- `SummaryStrip(List<SummaryCell>)`, `SummaryCell({label, value, semanticLabel})`: `SummaryStrip([SummaryCell(label: tr('Saved'), value: formatPts(3800)), ...])` 2 to 4 cells; becomes 2x2 at large text.
- `StatusChip(String label, {tone=StatusTone.neutral, icon})`; tones good, bad, warn, info, neutral: `StatusChip(tr('Paid'), tone: StatusTone.good)`
- `EmptyState(String text, {title, actionLabel, onAction})`: `EmptyState(tr('No loans yet.'), actionLabel: tr('Ask for credit'), onAction: f)`
- `Skeleton({width, height=16, radius=8})`: `Skeleton(width: 120)`; pulse, static if reduced motion.
- `SokoWordmark({size=30, header=false})`: "S[tomato]ko Kuu" in Fredoka bold, indigo on light, cream on dark; semantics label "Soko Kuu". Asset: `assets/brand/tomato_mark.png` (2.0x, 3.0x variants).
- `toast(context, msg, {error=false})`: icon + text, plain one-sentence wording.
- `reduceMotion(context)` helper.
- Still in widgets.dart: `Num`, `SectionTitle`, `AsyncBody`, `pts`, `bpPercent`, `titleCase`.

Themes: `buildTheme()` (light) and `buildDarkTheme()` in theme.dart. main.dart only uses `buildTheme()`; add `darkTheme: buildDarkTheme()` there to enable dark mode.
Rules: 48dp targets, works at text scale 2.0, no words wallet/token/stake/odds/jackpot/cash out/withdraw in user text, no casino cues, no streak or timer visuals.
