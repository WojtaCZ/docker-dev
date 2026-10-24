---
name: design-tokens-setup
description: Establish or audit a project's design token system — colour palette, typography scale, spacing, radius, shadow, and motion tokens — as CSS custom properties, Tailwind config, or a tokens JSON file.
---

Analyse the project's current styling approach and produce a complete, consistent design token layer. Adapt output format to the project (CSS custom properties, Tailwind `theme.extend`, Style Dictionary JSON, or a combination).

## Phase 1: Audit existing values
Scan the codebase for hard-coded colours, font sizes, spacing values, and radii. Group duplicates and near-duplicates. Identify the implicit palette and scale already in use.

## Phase 2: Produce the token set

### Colour
- **Primitives**: raw palette (e.g. `--color-blue-500: #3b82f6`). Aim for a 50–950 scale per hue.
- **Semantic aliases**: intent-based tokens that reference primitives:
  - `--color-bg-primary`, `--color-bg-surface`, `--color-bg-muted`
  - `--color-text-primary`, `--color-text-secondary`, `--color-text-disabled`
  - `--color-border-default`, `--color-border-strong`
  - `--color-accent`, `--color-accent-hover`
  - `--color-destructive`, `--color-success`, `--color-warning`
- **Dark mode**: show the semantic layer swap — primitives stay fixed, semantic tokens remap.

### Typography
- Type scale (base 16px, ratio 1.25 or 1.333): `--text-xs` through `--text-5xl`.
- Font families: `--font-sans`, `--font-mono`, `--font-display` (if any).
- Line heights and letter spacings paired per size.
- Font weights used (avoid using more than 3–4 weights).

### Spacing
- Consistent scale based on 4px or 8px base: `--space-1` (4px) through `--space-24` (96px).
- Component-level aliases: `--space-section-gap`, `--space-card-padding`.

### Radius
- `--radius-sm`, `--radius-md`, `--radius-lg`, `--radius-full`.

### Shadow / elevation
- 4–5 elevation steps: `--shadow-sm` through `--shadow-2xl`.

### Motion
- `--duration-fast` (100ms), `--duration-base` (200ms), `--duration-slow` (400ms).
- `--ease-default`, `--ease-in`, `--ease-out`, `--ease-spring`.

## Phase 3: Migration plan
List the top 10 hard-coded values by frequency with the token that should replace them. Provide a search-and-replace regex for each.
