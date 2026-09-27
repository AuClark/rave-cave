# Design

Every control page (dashboard :8080, Commander :8090, projection mapping :8100/edit, visuals :8110) uses one look: **charcoal, a hairline grid, one orange accent, and light geometric type**. The projector's output page (:8100/) doesn't; it's what the audience sees.

## Tokens

Each page defines these as CSS variables in its "design system" block.

| Token | Value | Use |
|---|---|---|
| `--bg` | `#242424` | page |
| `--panel` | `#2b2b2b` | panels and cards |
| `--well` | `#1f1f1f` | canvases, inputs, meters, the insides of things |
| `--line` / `--line2` | `#3e3e3e` / `#555` | hairlines / button and input outlines |
| `--text` / `--dim` | `#f2f2f2` / `#9a9a9a` | text / secondary text and labels |
| `--accent` | `#ff5a1f` | the one accent: active state, drops, master, deck 1, section numbers |
| `--good` / `--warn` / `--bad` | `#7ccf8a` / `#f2b84b` / `#ef5b5b` | status only, as outlines or text, rarely fills |

**Deck colours:** 1 orange, 2 light grey, then amber and green. rekordbox's track colour tags keep their own colours.

**Type:** Montserrat 300/400/500/600, with a system-font fallback so the pages work offline at a venue.
- **Big numbers and scene names:** weight 300, large.
- **Labels:** weight 500, uppercase, wide letter-spacing.

## Components

- **Top bar:** the page links, then the page's own view controls, on a row with a hairline under it. Whatever's active is underlined in orange.
- **Panels:** square, flat, divided by hairlines rather than floating with gaps. Section headings are numbered `01 — Name`, with the number in orange.
- **Buttons:** outlined rectangles. The edge goes orange on hover, and the button fills orange when on. Status tags are outlined in their status colour.
- **Page links:** the top bar of every control page has the same links (Decks, Lighting, Projection, Visuals), with the current page underlined in orange, so you never scroll to switch pages.

## Top bar and phones

- **One top bar on every page** (`.s5bar`, styled by `brain/common/web/s5auth.js`): 48 px (`--s5bar`, which everything pinned under it uses), never wraps. Logo (opens System) and page links on the left, in the same place on every page; page-specific bits fade in; the **SIM / NO DECKS** pill and the **lock** (orange view only, green admin) sit at the right end.
- **Phones (≤ 760 px):** the page links move to a bottom tab bar with icons: Lighting · Projection · **Decks** (middle) · Visuals · Stage. Pages must never be wider than the screen: tables and wide rows scroll sideways inside their panel.
- **Display first, controls in tabs:** on Lighting, Projection, Visuals and Stage the live view (Lighting's status and fixture strips, the projection preview, the visuals preview, the 3D stage) is pinned under the top bar, with **section tabs** under it (`S5AUTH.sectionTabs`); only the chosen section of controls shows, and the page remembers it. Projection and Visuals previews fill the width on phones and keep the projector's aspect ratio.
