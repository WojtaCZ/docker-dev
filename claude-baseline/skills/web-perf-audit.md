---
name: web-perf-audit
description: Audit a web page or codebase for Core Web Vitals regressions, bundle bloat, render-blocking resources, and back-end TTFB issues. Produces a prioritised fix list with estimated impact.
---

Conduct a web performance audit. Depending on what is provided (source code, Lighthouse JSON, network HAR, or URL), analyse across these dimensions:

## 1. Core Web Vitals targets
- LCP ≤ 2.5 s — identify the LCP element and what delays it (slow server, render-blocking CSS/JS, no preload, large image).
- INP ≤ 200 ms — identify long tasks on the main thread; flag event handlers that do synchronous work.
- CLS ≤ 0.1 — find unsized images/iframes, dynamically injected content above the fold, late-loading fonts causing FOUT.

## 2. Critical rendering path
- Render-blocking `<script>` without `defer`/`async`.
- Large synchronous CSS in `<head>` that could be inlined (critical) + deferred (rest).
- Third-party scripts loaded synchronously.

## 3. Asset optimisation
- Images: missing `width`/`height`, no `loading="lazy"` for below-fold, unoptimised format (JPEG where WebP/AVIF applies), no responsive `srcset`.
- Fonts: system font stack vs custom; `font-display: swap`; subsetting; self-hosted vs CDN.
- JS bundles: unused exports (tree shaking failures), heavy dependencies with lighter alternatives, unnecessary polyfills.
- CSS: dead selectors, large utility-class bundles that could be purged.

## 4. Caching & delivery
- Missing or short cache-control on static assets.
- No CDN for static assets.
- No HTTP/2 or HTTP/3.
- Large uncompressed responses (Brotli/gzip).

## 5. Server / TTFB
- TTFB > 600 ms — flag N+1 queries, missing DB indexes, synchronous external API calls in the critical path, no edge caching.

## 6. JavaScript execution
- Main-thread blocking during load (long tasks > 50 ms).
- Unnecessary hydration of static content.
- Missing code splitting / lazy routes.

For each finding state: severity (P0–P3), estimated LCP/INP/CLS delta if fixed, and the concrete code or config change needed.
