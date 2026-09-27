# Sektor5 brand

**App logo: the stencil wordmark** (`sektor5-stencil-*.svg`, 568 × 100). It's cut from heavy, chamfered stencil letters, with **SEKTOR** in the text colour and the **5** in orange `#ff5a1f`. On the rig's pages it's inline SVG: `.s5word` takes `--text` and `.s5five` takes `--accent`. It's drawn as plain paths, with no font, mask or ids. The favicon (`sektor5-stencil-favicon.svg`) is the orange stencil 5 on charcoal.

Earlier set (radar mark + Michroma wordmark), kept for reference:

| File | Use |
|---|---|
| `sektor5-stencil-current/white/black.svg` | Stencil wordmark (the app logo) |
| `sektor5-stencil-favicon.svg` | Favicon: stencil 5 |
| `sektor5-logo-*.svg` | Mark + wordmark, horizontal (137.46 × 24) |
| `sektor5-wordmark-*.svg` | Wordmark only (105.46 × 9.6) |
| `sektor5-mark-*.svg` | Mark only, square (24 × 24): favicons, small spaces |
| `png/` | Raster versions: `sektor5-mark-16/32/64/180/512.png`, `sektor5-logo-orange.png`, `sektor5-logo-orange-on-black.png` |

Variants: `black`, `white`, `orange`, and `current` (uses CSS `currentColor`, so it takes the surrounding text colour; used inline on the rig's pages).

- **Accent:** orange `#ff5a1f` (the pages' `--accent`). On the pages the mark is orange and the wordmark is in the text colour.
- **Type:** the wordmark is set in **Michroma** (SIL Open Font License, `Michroma-OFL.txt`), converted to outlines in the SVGs, so no font needs installing.
