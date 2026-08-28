# Pixel dog sprite recipe (24 × 24)

A baseline for building a front-view pixel dog with matching sitting / standing /
licking / sit-to-stand animations. Swap the palette and a few shape blocks to do a
different breed; keep everything else.

---

## 1. Canvas and scale

- Art grid: **24 × 24 pixels**, drawn on a `<canvas width="24" height="24">`.
- Display: CSS-scaled with `image-rendering: pixelated` (110 px preview, 288 px grid view).
- Export: **5× = 120 × 120 px** PNG per frame, transparent background.
- **Always leave a 1 px empty margin on all four sides.** The outline pass can only
  write inside the grid, so art flush against an edge loses its black border. This is
  the single most common bug.

## 2. Palette

| key | hex | use |
|---|---|---|
| `o` | `#F08A2A` | coat |
| `w` | `#FFFFFF` | chest, muzzle, blaze, paws |
| `p` | `#F5B3A8` | inner ear |
| `k` | `#1A1A1A` | outline, eyes, nose, mouth |
| `g` | `#CCCCCC` | soft chin shadow |
| `t` | `#EE7F8E` | tongue |
| `d` | `#D9647A` | tongue tip |

Max two coat tones. Everything else is white / outline / one accent.

### Neutrals must be true RGB neutrals

Any color meant to read as gray, black, or white must have **equal R, G and B channels**
— `#CCCCCC`, `#1A1A1A`, `#FFFFFF`. Warm off-neutrals like `#DDD7CF` or `#141210` look
correct on screen but pick up a visible yellow or brown cast the moment the art passes
through a color conversion (sRGB → device RGB in a game engine, indexed-palette PNG
export, a sprite atlas packer). Pixel art has so few pixels per shade that a 6-point
channel skew reads as a color shift, not a warm gray.

Rules:

- Grays, blacks, whites: **R = G = B**, always.
- Hue belongs only in the coat, inner ear, and tongue — the colors that are supposed to
  be colored.
- Write every value as a full 6-digit hex. No named CSS colors, no `rgba()` with alpha
  in the sprite itself — transparency comes from unpainted cells, not from partial alpha,
  so exported PNGs stay crisp and palette-safe.

## 3. Drawing primitives

One helper does all the work:

```js
rect(grid, x0, y0, x1, y1, color)  // inclusive bounds, clipped to the grid
```

**Draw order matters:**

1. lower half (body, legs, paws)
2. upper half (ears, head, blaze, muzzle) — drawn *after* so the head overlaps the body
3. outline pass
4. face details (eyes, nose, mouth, chin, tongue, hearts)

**Outline pass** — for every empty cell orthogonally adjacent to a filled cell, set `k`:

```js
const filled = grid.map(r => r.map(v => v !== null));
for (let y = 0; y < 24; y++) for (let x = 0; x < 24; x++) {
  if (filled[y][x]) continue;
  if ([[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([nx,ny]) =>
      nx>=0 && nx<24 && ny>=0 && ny<24 && filled[ny][nx])) grid[y][x] = k;
}
```

Face details go **after** the outline so they aren't swallowed by it.

## 3b. Outlined vs. outline-free

The same artwork ships either way. The rect geometry never changes — only what happens
after it is drawn.

### Adding an outline (the default)

Run the outline pass in section 3 on the finished shape, then draw face details on top.
The black ring grows OUTWARD into empty cells, so the silhouette gains 1 px on every
side. That is why the art needs a 1 px margin all round.

### Removing the outline

Do not simply delete the pass — the sprite goes flat and its edges dissolve. Replace it
with an **inward edge pass** plus three compensations:

**1. Darken the outermost ring of the shape itself.** Snapshot the grid first, then
recolour any filled pixel that has an empty orthogonal neighbour:

```js
const snapshot = grid.map(r => [...r]);
const isFilled = (x,y) => x>=0 && x<24 && y>=0 && y<24 && snapshot[y][x] !== null;
for (let y=0; y<24; y++) for (let x=0; x<24; x++) {
  if (!isFilled(x,y)) continue;
  if (![[x-1,y],[x+1,y],[x,y-1],[x,y+1]].some(([nx,ny]) => !isFilled(nx,ny))) continue;
  if (snapshot[y][x] === o) grid[y][x] = e;   // coat edge, e.g. #D9741C
}
```

Because it works inward the silhouette stays exactly the same size as the outlined
version — the two are drop-in swaps.

- **Only darken the coat.** Whites (chest, muzzle, paws) must stay pure; a gray edge
  around the paws reads as dirt.
- **Exempt narrow features.** Anything 2 px wide is *all* edge and turns solid dark.
  Skip the ear rows (`if (y < 5) continue;`) or the ears become dark stubs.

**2. Thicken the ears.** The black outline was adding ~2 px of visual mass per ear.
Without it, widen each ear rect by 1 px outward, and give the tip a flat 3-px top rather
than a taper — a pointed tip with no outline reads as a spike.

**3. Restore the rounding, and only at true silhouette corners.** The outline used to
soften hard corners. Clear a handful of outer corner pixels by hand:

```js
[[4,13],[19,13]].forEach(([x,y]) => { grid[y][x] = null; });
```

Rules learned the hard way:

- Clear only corners on the **outer** silhouette. Clearing an interior junction (where
  the legs meet the body) punches visible holes.
- Do not round the paw bottoms — keep them the full 3 px wide, or they look clipped.
- Where an ear meets the head, **fill** rather than clear: extend the ear's base rect
  toward the skull so no transparent notch is left between them.

**4. Watch for leftover divider lines.** Any `k`/`e` separation line copied from an
outlined pose runs AFTER the edge pass, so it paints brand-new opaque pixels outside the
silhouette instead of recolouring existing ones. Delete dividers the pose doesn't need,
and clip the ones it does to rows where the body actually exists.

Face details (eyes, nose, mouth, chin) stay black in both versions — they are what makes
the face read at 110 px, and they sit inside the shape so the edge pass never touches
them.

## 4. Baseline geometry

### Upper half — identical in every sprite, shifted by `h`

`h` is the vertical head offset. **`h = 1` is the standing baseline** (1 px margin at
the top); `h = 3` is fully seated.

```
ear L    (4,0+h)-(5,1+h)  (4,2+h)-(6,3+h)  (5,4+h)-(7,5+h)   o
ear L in (5,2+h)-(6,4+h)                                     p
ear R    (18,0+h)-(19,1+h) (17,2+h)-(19,3+h) (16,4+h)-(18,5+h) o
ear R in (17,2+h)-(18,4+h)                                   p
head     (6,4+h)-(17,12+h)                                   o
blaze    (11,4+h)-(12,8+h)                                   w
muzzle   (9,9+h)-(14,12+h)                                   w
```

### Face — follows `h`

```
eyes open   (9,6+h)-(9,7+h)   (14,6+h)-(14,7+h)              k
eyes half   (9,7+h)-(10,7+h)  (13,7+h)-(14,7+h)              k
eyes closed (8,7+h)-(10,7+h)  (13,7+h)-(15,7+h)              k
nose        (10,10+h)-(13,10+h) + (11,11+h)-(12,11+h)        k
mouth       (10,12+h) and (13,12+h)                          k
chin curve  (10,13+h)-(13,13+h) + (11,14+h)-(12,14+h)        g
```

### Lower half — standing

```
body        (5,12)-(18,18)     o
chest       (9,12)-(14,18)     w
hind paw L  (4,16)-(6,19) o  + (4,18)-(6,19) w
hind paw R  (17,16)-(19,19) o + (17,18)-(19,19) w
front paws  (8,18)-(10,21) w   (13,18)-(15,21) w
paw gap     (11,19)-(12,21)    k   ← drawn after the outline pass
```

### Lower half — sitting

```
body        (4,13)-(19,19)     o     (wider, rounder)
chest       (8,14)-(15,19)     w
front leg L (6,19)-(8,22) o  + (6,21)-(8,22) w
front leg R (15,19)-(17,22) o + (15,21)-(17,22) w
```

No hind paws and no paw gap when seated.

## 5. The three animations

All frames come from one `buildGrid(opts)` function; each animation only varies a few
parameters. Frames are pre-built once into an array, then a `setInterval` walks an
order list. Every frame in a sheet must be **unique** — duplicated frames are dead
weight in an export.

### Standing idle — 3 frames

| param | values |
|---|---|
| `h` | 1 (rest), 2 (bob down) |
| eyes | open, closed |

Frames: `h1 open`, `h2 open`, `h1 closed`. Play order `[0,1,0,2]` at **400 ms**.

### Licking — 11 frames

Fixed `h` bob of 1 → 2. Tongue grows from row `11+h` downward at x11–x12, pink `t`
with a `d` tip:

```js
rect(11, 12+h, 12, 11+h+len, t);   // len 1..4
rect(11, 11+h+len, 12, 11+h+len, d);
```

Three staged details make the open/close read smoothly:

- **snout**: closed mouth has the mouth corners `(10,12+h)`, `(13,12+h)`; they drop first.
- **chin**: `full` (both gray rows) → `narrow` (bottom row only) → `off`. Ease it out on the
  way open *and* back in on the way closed.
- **eyes**: open → half → closed as the tongue extends.
- **hearts**: 3 × 3 pink glyph beside the head, `(20,y)`,`(22,y)`,`(20..22,y+1)`,`(21,y+2)`,
  rising from y = 8 to y = 5; a second heart on the left at the peak.

Play in order at **150 ms**.

### Sit → stand — 5 frames

Head and body move together. `h = [3, 3, 2, 1, 1]` while the lower half interpolates
from the sitting block to the standing block: body top 13 → 13 → 13 → 12 → 12, hind
paws fade in from stage 1, front legs shorten from rows 19–22 to 18–21.

Play order `[0,0,0,1,2,3,4,4,4,4,3,2,1]` at **220 ms** — holds on both ends so the
motion reads as a deliberate stand-up.

### Tail spin (rotation) — 9 frames

The hard one: a full turn on the spot. It is the only animation that needs poses other
than the front view, so it carries its own rules.

**Frame order** — front → ¾ → side → rear ¾ → back → rear ¾ (mirrored) → side
(mirrored) → ¾ (mirrored), with a clean **standing frame first** so the clip starts
from the shared baseline:

```
0 front, no tail        (identical to the standing sprite's rest frame)
1 front, tail nub showing
2 three-quarter
3 side
4 rear three-quarter
5 back
6 rear three-quarter, mirrored
7 side, mirrored
8 three-quarter, mirrored
```

Play straight through at **130 ms**.

**Mirror the second half.** Write only the right-turning poses and derive the left ones:

```js
mirror(grid) { return grid.map(row => [...row].reverse()); }
```

Half the drawing, and the loop is guaranteed symmetric. Asymmetric markings would break
this — add those as a post-mirror pass if the breed needs them.

**Keep the silhouette mass consistent across views.** The failure mode is a side view
that is much longer and lower than the front view, so the rotation reads as the dog
inflating and deflating rather than turning. Body roughly 13 px wide × 8 tall in every
view; if a pose feels too drastic next to its neighbours, it is.

**Side view.** Corgis have almost no neck — the head must sit LOW, overlapping the
body's top rows, not perched on a column above them. A head placed above the shoulders
turns the sprite into a llama. Head rows 7–14 against a body starting at row 10 works;
the snout protrudes forward as a white block off the head's leading edge.

**Back view.** No face at all — solid coat, ears splayed as usual, no blaze and no
muzzle. Flare the body outward below the shoulders and put white fluff around the tail
base: this is the "big fluffy butt" frame and it needs a wider silhouette than the front
view, or the rotation stalls visually. Bottom edge is a **straight line** — drop the
front paws, keep only the outboard hind paws.

**Tail.** A stump, not a plume: 2 px wide, 4–5 rows tall, orange with a white tip. Big
in the back and rear-¾ views, a small nub in ¾, barely visible in front.

### Draw order gotchas for non-front views

Three bugs cost several rounds on the tail spin. All are ordering problems:

1. **Ears after the head.** Ear rects drawn before the head get overwritten by the head
   block, collapsing them to nubs with a 1 px pink sliver. Draw ears last (before the
   outline pass) so the authored shape survives.
2. **The tail is the nearest element in rear views.** Draw it after the head and body,
   and give it its own explicit black border — the silhouette outline pass only borders
   the outer edge, so an orange tail on an orange rump is invisible.
3. **Separation lines must span the whole overlap, and must not land on an edge
   column.** A divider covering only part of the seam leaves a black dash floating
   inside the silhouette; a divider painted on the body's own edge column blackens the
   body instead of the gap. Where two same-colour masses meet (head/body from behind,
   tail/rump in side view), run the `k` line the full width or height of the contact.

Related: any interior detail (chin gray, markings) drawn **outside** its parent shape
strands single pixels once the outline pass runs. Keep face details inside the head
block, and check for lone white pixels boxed in by black.

### Chaining
Because standing, licking, and the last sit-to-stand frame all sit at `h = 1` with the
same lower half, the clips cut together without a jump. Keep that rule for any new pose.

## 6. Export

- **Sprite sheet**: one canvas `24*scale*n` wide, frames drawn left to right, `toDataURL('image/png')`.
- **Individual frames**: browsers block multiple sequential downloads, so bundle them
  into a **stored (uncompressed) ZIP** — local file header + central directory + EOCD,
  with a CRC-32 per entry — and download the single blob. Name frames zero-padded
  (`frame-01.png`) so they sort correctly.

## 7. Adapting to another breed

Change only these; leave the grid, offsets, draw order, outline pass and timings alone:

1. **Palette** — coat and inner-ear colors.
2. **Ear block** — the three `rect` calls per ear. Pointed and upright as above; for
   floppy ears drop the tip rows and extend down the sides of the head instead.
3. **Blaze / muzzle** — widen, narrow, or delete the blaze; move the muzzle rows.
4. **Body silhouette** — corgis are wide and low. A leggier breed raises the body top
   row and lengthens the legs; keep the 1 px margin at the bottom.
5. **Markings** — add as a post-outline pass so the outline doesn't eat them.

Everything else (h values, animation frame lists, export code) carries over unchanged.
