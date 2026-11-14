# Design System Master File

> **Reconciled 2026-11-14:** the generator's palette (pink/purple) and fonts (Caveat/Quicksand) were replaced with Soko Kuu's
> existing brand, which the app already ships: indigo, terracotta, gold, maroon `#8A1F2E`, sukuma green `#1F6B62`, cream,
> Fredoka + DM Sans, kitenge zig-zag strip, the "Nyanya Juu" tomato logo. The claymorphism style guidance below is kept.


> **LOGIC:** When building a specific page, first check `design-system/pages/[page-name].md`.
> If that file exists, its rules **override** this Master file.
> If not, strictly follow the rules below.

---

**Project:** Soko Kuu
**Generated:** 2026-11-14 09:37:57
**Category:** Casual Puzzle Game
**Design Dials:** Variance 5/10 (Balanced / Modern) | Motion 4/10 (Standard) | Density 4/10 (Standard)

---

## Global Rules

### Color Palette

| Role | Hex | CSS Variable |
|------|-----|--------------|
| Primary (indigo) | `#2E3A8C` | `--color-primary` |
| On Primary | `#FFFFFF` | `--color-on-primary` |
| Secondary (terracotta) | `#B8452E` | `--color-secondary` |
| Accent (market gold) | `#E8A93A` | `--color-accent` |
| Background (cream) | `#F6EBDA` | `--color-background` |
| Foreground | `#0F172A` | `--color-foreground` |
| Muted | `#FDF4F8` | `--color-muted` |
| Border | `#FCE9F2` | `--color-border` |
| Destructive | `#DC2626` | `--color-destructive` |
| Ring | `#EC4899` | `--color-ring` |

**Color Notes:** Cheerful pink + reward gold

### Typography

- **Heading Font:** Fredoka (bundled, OFL)
- **Body Font:** DM Sans (bundled, OFL)
- **Mood:** friendly, chunky, warm, Kenyan market
- **Fonts:** shipped in `app/assets/fonts/` (no network fetch)

**CSS Import:**
```css
@import url('https://fonts.googleapis.com/css2?family=Caveat:wght@400;500;600;700&family=Quicksand:wght@300;400;500;600;700&display=swap');
```

### Spacing Variables

*Density: 4/10 — Standard*

| Token | Value | Usage |
|-------|-------|-------|
| `--space-xs` | `4px` / `0.25rem` | Tight gaps |
| `--space-sm` | `8px` / `0.5rem` | Icon gaps, inline spacing |
| `--space-md` | `16px` / `1rem` | Standard padding |
| `--space-lg` | `24px` / `1.5rem` | Section padding |
| `--space-xl` | `32px` / `2rem` | Large gaps |
| `--space-2xl` | `48px` / `3rem` | Section margins |
| `--space-3xl` | `64px` / `4rem` | Hero padding |

### Shadow Depths

| Level | Value | Usage |
|-------|-------|-------|
| `--shadow-sm` | `0 1px 2px rgba(0,0,0,0.05)` | Subtle lift |
| `--shadow-md` | `0 4px 6px rgba(0,0,0,0.1)` | Cards, buttons |
| `--shadow-lg` | `0 10px 15px rgba(0,0,0,0.1)` | Modals, dropdowns |
| `--shadow-xl` | `0 20px 25px rgba(0,0,0,0.15)` | Hero images, featured cards |

---

## Component Specs

### Buttons

```css
/* Primary Button */
.btn-primary {
  background: #F59E0B;
  color: white;
  padding: 12px 24px;
  border-radius: 8px;
  font-weight: 600;
  transition: all 200ms ease;
  cursor: pointer;
}

.btn-primary:hover {
  opacity: 0.9;
  transform: translateY(-1px);
}

/* Secondary Button */
.btn-secondary {
  background: transparent;
  color: #EC4899;
  border: 2px solid #EC4899;
  padding: 12px 24px;
  border-radius: 8px;
  font-weight: 600;
  transition: all 200ms ease;
  cursor: pointer;
}
```

### Cards

```css
.card {
  background: #FDF2F8;
  border-radius: 12px;
  padding: 24px;
  box-shadow: var(--shadow-md);
  transition: all 200ms ease;
  cursor: pointer;
}

.card:hover {
  box-shadow: var(--shadow-lg);
  transform: translateY(-2px);
}
```

### Inputs

```css
.input {
  padding: 12px 16px;
  border: 1px solid #E2E8F0;
  border-radius: 8px;
  font-size: 16px;
  transition: border-color 200ms ease;
}

.input:focus {
  border-color: #EC4899;
  outline: none;
  box-shadow: 0 0 0 3px #EC489920;
}
```

### Modals

```css
.modal-overlay {
  background: rgba(0, 0, 0, 0.5);
  backdrop-filter: blur(4px);
}

.modal {
  background: white;
  border-radius: 16px;
  padding: 32px;
  box-shadow: var(--shadow-xl);
  max-width: 500px;
  width: 90%;
}
```

---

## Style Guidelines

**Style:** Claymorphism

**Keywords:** Soft 3D, chunky, playful, toy-like, bubbly, thick borders (3-4px), double shadows, rounded (16-24px)

**Best For:** Educational apps, children's apps, SaaS platforms, creative tools, fun-focused, onboarding, casual games

**Key Effects:** Inner+outer shadows (subtle, no hard lines), soft press (200ms ease-out), fluffy elements, smooth transitions

### Page Pattern

**Pattern Name:** App Store Style Landing

- **Conversion Strategy:** Show real screenshots. Include ratings (4.5+ stars). QR code for mobile. Platform-specific CTAs.
- **CTA Placement:** Download buttons prominent (App Store + Play Store) throughout
- **Section Order:** 1. Hero with device mockup, 2. Screenshots carousel, 3. Features with icons, 4. Reviews/ratings, 5. Download CTAs

---

## Motion

**Stagger List** (Standard) — Trigger: load or scroll | Duration: 300-450ms | Easing: `back.out(1.4)`

```js
gsap.from('.grid-item', { opacity: 0, scale: 0.92, y: 16, duration: 0.4, stagger: { each: 0.06, from: 'start', grid: 'auto' }, ease: 'back.out(1.4)' });
```

**Framework notes:** grid: 'auto' lets GSAP infer rows/columns from a CSS grid layout for a natural wave stagger

- ✅ Combine with from: 'center' for a bento-grid layout to draw the eye inward first
- ❌ Don't use back.out on dense data tables; the overshoot reads as sloppy on informational UI
- ⚡ Group DOM writes; avoid interleaving layout reads (getBoundingClientRect) between staggered tweens

---

## Anti-Patterns (Do NOT Use)

- ❌ Muted colors
- ❌ Low energy

### Additional Forbidden Patterns

- ❌ **Emojis as icons** — Use SVG icons (Heroicons, Lucide, Simple Icons)
- ❌ **Missing cursor:pointer** — All clickable elements must have cursor:pointer
- ❌ **Layout-shifting hovers** — Avoid scale transforms that shift layout
- ❌ **Low contrast text** — Maintain 4.5:1 minimum contrast ratio
- ❌ **Instant state changes** — Always use transitions (150-300ms)
- ❌ **Invisible focus states** — Focus states must be visible for a11y

---

## Pre-Delivery Checklist

Before delivering any UI code, verify:

- [ ] No emojis used as icons (use SVG instead)
- [ ] All icons from consistent icon set (Heroicons/Lucide)
- [ ] `cursor-pointer` on all clickable elements
- [ ] Hover states with smooth transitions (150-300ms)
- [ ] Light mode: text contrast 4.5:1 minimum
- [ ] Focus states visible for keyboard navigation
- [ ] `prefers-reduced-motion` respected
- [ ] Responsive: 375px, 768px, 1024px, 1440px
- [ ] No content hidden behind fixed navbars
- [ ] No horizontal scroll on mobile
