# Coding Strategy: Dog Animation Watchface

## Overview
Build a Garmin watchface for the Fenix 7S Pro featuring a corgi character with animated behaviors, displaying time, date, steps, and battery. Implementation is phased from simplest to most complex, with each phase verified in the simulator before proceeding.

See [boilerplate-context.md](boilerplate-context.md) for SDK and codebase reference.

---

## Architecture

### Drawing Model
All rendering is done via direct `dc` calls in `onUpdate`. The XML layout (`layout.xml`) will be replaced. Draw order each frame:

1. Clear background (solid color fill)
2. Draw dog sprite (current animation frame)
3. Draw info overlays: time, date, steps, battery

### Animation Model
A `Toybox.Timer` drives animation. It fires at ~100ms intervals, increments a frame index, and calls `WatchUi.requestUpdate()`. `onUpdate` reads the current frame index and draws the corresponding bitmap.

- Timer is **started** in `onExitSleep()` and **stopped** in `onEnterSleep()`
- In sleep mode, the watchface updates at 1fps (standard for Garmin watchfaces) — show only the static sitting pose
- Animation state machine: an enum-style variable (`mAnimState`) controls which animation is active; frame index resets on state change

### Sprite Assets
Each animation is a set of indexed PNG files stored in `resources/drawables/`. Loaded once in `onLayout` into instance variables, freed in `onHide`.

Frame counts are estimates — finalize when assets are created:
| Animation | Est. Frames | Notes |
|-----------|-------------|-------|
| Sit (idle) | 1 | Base pose, also used in sleep mode |
| Blink | 3 | Open → half → closed, then reverse |
| Lick | 4 | Tongue out sequence, dog stays seated |
| Bark + hearts | 4 | Mouth open/close + floating heart drawable |
| Tail spin | 10–12 | Full rotation, most complex |

### Info Layout (static regions, drawn each frame)
Designed for a 260×260 round screen. Exact coordinates to be tuned in simulator:
- **Time**: large font, center of upper half (~y=90)
- **Date**: small font, below time (~y=120)
- **Steps**: bottom-left quadrant with icon
- **Battery**: bottom-right quadrant with icon or bar

---

## Phases

### Phase 1 — Static Watchface with Sitting Dog
**Goal**: Correct info display + dog visible. No animation.

Tasks:
1. Replace `setLayout` / `TimeLabel` approach with direct `dc` drawing in `onUpdate`
2. Draw time (large, centered), date (small, below time), steps (bottom-left), battery (bottom-right)
3. Add `ActivityMonitor` and `System.getSystemStats()` data reads
4. Create or source a single static corgi sprite (sitting pose, PNG, ~120×120px)
5. Load sprite in `onLayout`, draw at center of lower half in `onUpdate`
6. Add `<uses-permission id="com.garmin.connectiq.permission.FIT_FIELDS"/>` to manifest for ActivityMonitor

**Verification**: Simulator shows correct time updating each second, readable date, step count and battery visible, dog image centered in lower half.

---

### Phase 2 — Blinking Eyes
**Goal**: Dog blinks at a natural random interval while sitting. Simplest animation — only the eye region changes.

Tasks:
1. Create 3-frame blink sprites (or overlay eye-region PNGs on top of base sitting sprite)
2. Implement `Toybox.Timer` in `DogAnimationExperimentView`: start in `onExitSleep`, stop in `onEnterSleep`
3. Add `mAnimState` variable; for Phase 2 it is always `BLINK`
4. Blink cadence: play the 3-frame sequence quickly (~80ms/frame), then hold open for 3–5 seconds (randomized with `Math.rand()`)
5. Timer callback: advance frame, call `requestUpdate()`

**Verification**: Dog blinks periodically in simulator. Stops animating when simulator enters sleep mode.

---

### Phase 3 — Lick and Bark Animations
**Goal**: Dog plays a lick or bark animation at random intervals, returns to sit/blink idle.

Tasks:
1. Create lick sprite frames (tongue extends toward screen, 4 frames)
2. Create bark sprite frames (mouth opens, small heart drawables float up, 4 frames)
3. Extend state machine: `IDLE` (sit + blink) → randomly trigger `LICK` or `BARK` every 30–90 seconds
4. Play full animation sequence, then return to `IDLE`
5. Hearts for bark: draw `Graphics` primitives (filled circle + small rectangle = simple heart) at offset positions per frame, or use a small heart PNG overlay

**Verification**: Both animations play through completely and return to idle. Timing feels natural — not too frequent, not too rare.

---

### Phase 4 — Tail Spin
**Goal**: Dog occasionally chases its tail (full rotation animation).

Tasks:
1. Create 10–12 frame tail-spin sprite sequence (dog body rotating, tail chasing)
2. Add `TAIL_SPIN` state to state machine
3. Integrate into idle random trigger pool alongside lick and bark
4. Tune playback speed (~80–100ms/frame) for a natural spinning feel

**Verification**: Tail spin plays smoothly in simulator with no visible frame stutter. Returns to idle correctly.

---

## Asset Creation Strategy
Sprites can be sourced or created in two ways:

**Option A — Pixel art (recommended for first pass)**: Use a tool like Aseprite or Pixilart to draw a small corgi (~100×100px) and its animation frames. Export as indexed PNG. Simple enough to do frame-by-frame.

**Option B — Reference existing**: The [Garmin Corgi watchface](https://apps.garmin.com/apps/d5cf60d2-4ec6-4450-b082-0b3a9adea6bd) and [vscode-pets](https://github.com/tonybaloney/vscode-pets) are reference examples for art style and frame structure.

Sprite size: target **~110×110px** to leave room for the info overlays on a 260×260 screen.

---

## Testing Documentation
Each phase should include a companion test note (in this `planning/` directory) covering:
- What was tested in the simulator
- Edge cases checked (sleep mode, 12/24h toggle, low battery display, midnight rollover)
- Any known issues or deferred items

---

## Deferred
- Developer key signing (needed only for device sideload / store submission, not simulator)
- Multi-language support
- Settings UI (background color, foreground color toggles from boilerplate can remain as-is for now)
- Performance profiling (only needed if frame drops are observed)
