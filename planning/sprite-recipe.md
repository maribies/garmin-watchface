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
