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

- **Top bar:** a nav row with a hairline under it. The active view is underlined in orange.
- **Panels:** square, flat, divided by hairlines rather than floating with gaps. Section headings are numbered `01 — Name`, with the number in orange.
- **Buttons:** outlined rectangles. The edge goes orange on hover, and the button fills orange when on. Status tags are outlined in their status colour.
- **Bottom tiles:** every control page ends with the same four tiles (Deck link, Commander, Projection, Visuals), each with an arrow. The current page's tile is light, with an orange arrow block.
