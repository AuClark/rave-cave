# Design

Every control page (dashboard :8080, Commander :8090, projection mapping :8100/edit, the Stage view, visuals :8110) uses one look: **near-black and flat, zinc neutrals with 1 px borders, one orange accent, system type, sentence case**. Somewhere between a Pioneer screen, Ableton and shadcn. The projector's output page (:8100/) doesn't; it's what the audience sees.

## Where it lives

- **The shared theme** is in `brain/common/web/s5auth.js` (`themeCss()`), which every control page loads. It's appended last in `<head>`, so it wins over each page's own styles: the tokens, type, sentence case, control shapes, focus rings, inputs and scrollbars. Change the look there first.
- **Each page's own "design system" block** still sets its layout. Its colours are on the same neutral scale (below), so a page and the theme agree even where the theme doesn't reach, like canvas drawing.
- The top bar, section tabs and phone tab bar are styled in the same file (`barCss`).

## Tokens

| Token | Value | Use |
|---|---|---|
| `--bg` | `#0c0c0e` | page |
| `--panel` / `--card` | `#131316` | panels and cards |
| `--well` | `#08080a` | canvases, inputs, meters, the insides of things |
| `--line` / `--line2` | `#26262b` / `#3a3a41` | hairlines / button and input outlines |
| `--text` / `--dim` / `--faint` | `#fafafa` / `#a1a1aa` / `#6b6b74` | text / secondary text / hints |
| `--accent` | `#ff5a1f` | the one accent. It means live or on: an active button, drops, master, deck 1 |
| `--good` / `--warn` / `--bad` | `#4ade80` / `#fbbf24` / `#ef4444` | status only, as outlines or text, rarely fills |

**Deck colours:** 1 orange, 2 light grey, then amber and green. rekordbox's track colour tags keep their own colours.

**Type:** system fonts (Inter if installed, then SF / Segoe / Roboto). Nothing is fetched from the web: the brain is often offline at a venue.
- **Sentence case everywhere**, no uppercase labels or letter-spacing. The theme enforces it, so write labels the way they should read. Acronyms (BPM, USB, DJ) stay as they are.
- **Big numbers and scene names:** light weight, large.
- **Headings:** 600, in the dim colour.

## Components

- **Top bar:** the logo, then the page links as quiet text with the current page in a white pill, then the page's own controls. The **SIM / NO DECKS** pill and the **lock** sit at the right end.
- **Section tabs:** a row of quiet text tabs; the chosen one sits in a raised pill.
- **Buttons:** 8 px corners, a 1 px outline that brightens on hover, filled orange when on. Pressing nudges them down half a pixel.
- **Inputs and selects:** the well colour, a 1 px outline, and an orange focus ring.
- **Status tags:** small, 6 px corners, outlined in their status colour.
- **Pictures** (previews, the stage): soft 12 px corners where they sit in a page.

## Top bar and phones

- **One top bar on every page** (`.s5bar`, styled by `brain/common/web/s5auth.js`): 48 px (`--s5bar`, which everything pinned under it uses), never wraps. Logo (opens System) and page links on the left, in the same place on every page; page-specific bits fade in; the **SIM / NO DECKS** pill and the **lock** (orange view only, green admin) sit at the right end.
- **Phones (≤ 760 px):** the page links move to a bottom tab bar with icons: Lighting · Projection · **Decks** (middle) · Visuals · Stage. Pages must never be wider than the screen: tables and wide rows scroll sideways inside their panel.
- **Display first, controls in tabs:** on Lighting, Projection, Visuals and Stage the live view (Lighting's status and fixture strips, the projection preview, the visuals preview, the 3D stage) is pinned under the top bar, with **section tabs** under it (`S5AUTH.sectionTabs`); only the chosen section of controls shows, and the page remembers it. Projection and Visuals previews fill the width on phones and keep the projector's aspect ratio.
