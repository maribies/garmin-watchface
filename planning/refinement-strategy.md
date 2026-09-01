# Refinement Strategy

Phases 1-4 in [coding-strategy.md](coding-strategy.md) got a working watchface: static info display, a standing-idle blink loop, and three random tricks (lick, sit-down/stand-up, tail spin). This doc plans the next round — a visual redesign plus new data-driven behaviors — refined from the original brainstorming notes against the actual Connect IQ SDK docs (`doc/` and `samples/` in the SDK install) rather than guesses and assumptions. API findings have been added to [boilerplate-context.md](boilerplate-context.md).

Before starting on Phase A, this doc (and the current codebase) went through an in-depth, staff-engineer-level review — looking for scalability and correctness risk ahead of adding more sprites/triggers, not just checking that the plan reads well. That review produced Phase 0 below, plus a few items folded into Deferred.

## Phase 0 — Resolve before further additions

Surfaced by the in-depth review mentioned above. Both items block Phase A/B until resolved, since they affect how much room there actually is to work with.

**Goal:** Confirm we're not already over the sprite memory budget, and stop the render/dispatch code from growing linearly with every new trick.

1. ~~Resolve the sprite memory question.~~ **Resolved**, via an isolated test project bisecting actual runtime behavior (not build success, which turned out to prove nothing — see below):
   - **No compile-time enforcement exists at all.** A single 10MB dummy bitmap resource compiles clean with `monkeyc -w`, zero warnings. The 128KB `watchFace` figure in `compiler.json` is never checked against bitmap resources at build time — "build succeeded" was never validating memory safety, the whole session.
   - **Runtime enforcement is real**, confirmed via the actual thrown exception: `WatchUi.loadResource()` raises `Exception: The requested memory could not be allocated from the graphics memory pool` once a resource is too large. Bisected the exact single-resource threshold: passes at 512,000 bytes, fails at 524,288 bytes.
   - **The limit is per-resource, not cumulative.** Three simultaneous 200,000-byte resources (600,000 bytes total) all loaded fine — past the point where one 524,288-byte resource alone fails. So there's a distinct "graphics memory pool" capping each individual bitmap allocation (~512-524KB each), separate from the 131,072-byte `watchFace` app-memory figure, which governs something else (general code/heap) and was never the right number to compare bitmap sizes against.
   - **Conclusion:** our current 5 sheets total ~237,600 bytes (4bpp-estimated), largest single sheet ~79,200 bytes. Phase B's three new sheets bring the total to ~403,200 bytes, largest single sheet still ~79,200 bytes. Every individual sheet sits around 15% of the real per-resource ceiling, and since the limit isn't cumulative, the totals aren't a risk either. The original concern was a wrong mental model (comparing against the wrong number), not an actual problem — no further sprite-size caution needed beyond normal common sense.
2. ~~Stop the per-trick fan-out.~~ **Resolved.** Replaced the three growing if/else chains (`onAnimTimer`'s state dispatch, `configureTimerForState`, the bitmap-selection block in `onUpdate`) with a table-driven model: each trick is an `Array` of clips (`{:bitmap, :startFrame, :frameCount, :tickMs, :repeat}`), played in sequence by one generic `nextClipProgress()` step function. Single-clip tricks (lick, tail spin) and the multi-clip trick (sit-down → hold → stand-up) are now the same shape — a trick with one clip vs. three. Adding a trick is now one entry in the `mTricks` array built in `onLayout`; nothing else needs touching. `pickTrickIndex()` also generalized from a hardcoded 3-way branch to `raw % trickCount`, so the random pool auto-adjusts as tricks are added. Verified behaviorally identical to the original: all 6 tests pass (including a generalized version of the multi-clip sequencing test, now parameterized over any clip-frame-count list rather than hardcoded to the sit/stand trick specifically), and release builds are clean on all three target devices.

**Verification:** Memory — done, via the isolated bisection test above (real thrown exceptions at measured thresholds, not absence-of-warning). Architecture — done: adding a trick is now a single `mTricks` entry instead of a three-file touch, confirmed by the refactor being a drop-in behavioral match (same tests, same tick counts, same completion signals) for the three existing tricks.

**Phase 0 is complete.** Both items resolved — clear to start Phase A/B.

---

## Phase A — Watch face redesign

**Goal:** Clearer, more inclusive info display; user-configurable background color and data fields.

1. **Icons.** Replace the "steps" text label with a feet icon, add a battery icon with charge-level variants (full/three-quarters/half/quarter/empty) selected from `System.getSystemStats().battery`. Icons to the right of the numeral they describe, per the original notes. Source as SVG directly from FontAwesome — the resource compiler supports SVG `<bitmap>` resources natively (no PNG conversion step; confirmed both by the SDK's Resources doc and by our own already-working `launcher_icon.svg`), so no separate art pipeline needed the way the corgi sprites required one. Add under `resources/drawables/` (an `icons/` subfolder, matching the `corgi/` convention) and declare each in `drawables.xml` the same way `LauncherIcon` already is. Still verify the rasterized pixel colors are `ARGB2222`-safe once real icons are in, same diligence as the sprite gray issue — vector source doesn't exempt it from that.
2. **Background colors.** Extend the existing (currently unused) `resources/settings/properties.xml` + `settings.xml` scaffold — this is the `Properties_and_App_Settings` mechanism (on-device Settings menu / Garmin Connect mobile app), works on every device we support. (Correction: an earlier version of this doc cited the `ConfigurableWatchFace` SDK sample here — that sample is actually built around the *native, fēnix 8+-only* long-press watch face editor, a different mechanism; see Deferred.) Add 6 light shades (red, blue, yellow, green, purple, orange), each `ARGB2222`-safe. Decide during implementation whether text stays black or shifts to a darker tint of the background — flagged in the original notes as needing a visual check, not a design decision to make blind.
3. **Configurable data fields.** Same Settings-menu mechanism as background color, uniform across all supported devices (`fenix7pro`, `fenix7pronowifi`, `fenix7s`, `fenix7spro`, `fenix8solar47mm`) rather than branching for fēnix 8's native field editor — see Deferred. 3-5 slots, each user-selectable from: steps (existing), battery (existing), heart rate, weather, body battery. Date/time stay fixed and always shown, per the original notes' priority ordering. Layout: worth experimenting with the dog sprite off-center (left or right) so fields have a consistent side to live on, rather than assuming the current centered layout survives this change.

   **Decided:** field selection is Settings-driven (same mechanism as background color), and only data for currently-selected fields is fetched/subscribed — generalizes the heart-rate-specific "only call if selected" note to every field, including unsubscribing a `Complications` field the user deselects mid-use, not just at view show/hide.

   **Still open, decide before building this item:**
   - Settings shape — one Property per slot (`Field1`…`Field5`, each a list picking from {none, steps, battery, heart rate, weather, body battery}), or some other scheme?
   - Layout when fewer than the max slots are chosen — do unused positions go blank, or does the layout re-flow/re-center around however many are actually selected?
   - A uniform per-field render path (e.g. a struct/function taking icon + value + fallback text) so `onUpdate` loops over selected fields identically regardless of type, rather than a growing per-field if/else the way trick dispatch already does (the thing Phase 0 item 2 is fixing for tricks — worth not reintroducing the same shape here).
4. Second dog breed stays deferred, unscoped, per the original notes' "eventually."

**Verification:** Each new icon/color/field checked live in the simulator — pixel alignment, `ARGB2222` color fidelity, and (for weather) the fallback state when `CurrentConditions` is null.

---

## Phase B — New animated behaviors

**Goal:** More triggers wired into the existing random-trick state machine, using the sprite sheets already on disk.

Assets already present (frame counts inferred from sheet width ÷ 120px, same as the existing sheets — frame order and per-frame timing still need deciding the same way we did for tail spin: inspect actual pixel alignment, propose a play order, confirm live):

| Sheet | Frames |
|---|---|
| `corgi-foot-taps-sheet.png` | 5 |
| `corgi-sploot-front-sheet.png` | 8 |
| `corgi-sploot-rear-sheet.png` | 10 |

1. **Feet tappies.** Triggers: added to the existing random trick pool (alongside lick/sit-stand/tail-spin), plus a `COMPLICATION_TYPE_NOTIFICATION_COUNT` increase.
2. **Laying down (sploot).** Two sheets exist (front and rear/"butt showing," per the original notes' preference) — decide during implementation whether both play as a sequence or the rear view is the only one used. Triggers: low battery, activity goal reached (`Info.steps` vs `.stepGoal`), near-bedtime (`UserProfile.sleepTime`).
3. **Move-alert trigger** (lower priority, per your note — worth doing, just not first). Reuses an existing animation (candidates: tail spin, or the new sploot/foot-taps once built) when `moveBarLevel` reaches `MOVE_BAR_LEVEL_MAX`.
4. **Heart-rate-triggered lick.** Reuses the existing lick animation; fires when a recent `getHeartRateHistory()` sample notably exceeds `UserProfile.restingHeartRate`. **Decide implement-vs-defer right before building this item, not now:** heart-rate patterns may not be reliably discernible for a good trigger, and the extra `getHeartRateHistory()` checking has a battery cost that might not be worth it for something this uncertain — weigh that against Phase A's field display already needing HR reads (see `boilerplate-context.md`), which lowers the marginal cost of also using it as a trigger. If the decision is to skip it, nothing is lost: lick already fires on its own via the existing random trick pool regardless.

**Verification:** Each new trigger confirmed live — both that the condition actually fires (may need temporarily-relaxed thresholds the way we shortened the trick-trigger window in Phase 3, to test without waiting for a real low-battery/bedtime moment) and that the animation renders correctly via the `setClip`+`drawBitmap` approach already proven for the existing sheets.

---

## Testing, as we go

Two kinds of verification, and neither substitutes for the other — this bit us twice already (the `drawBitmap2` cropping bug and the sit/stand sequencing bug were each invisible to the other kind of check):

**Automated (`Toybox.Test`, `monkeyc -t` / `monkeydo -t`)** — for logic that doesn't need pixels on screen:
- Threshold/comparison logic: move-bar-max check, notification-count delta detection, low-battery threshold, weather refresh-time-window check.
- Data formatting/fallback logic: what gets drawn when `CurrentConditions`/a `Complications` value is null.
- Any new trick-sequencing state machine (mirroring `nextTrickStep` / `testTrickSequenceWalksSitPauseStand`), if a new trick needs multi-state playback like sit-down/stand-up did.
- Resource loading for each new sheet, folded into the existing `testAllDrawablesLoad` rather than a new one-off test per sheet.
- New color values are `ARGB2222`-safe (a pure function checking each channel is in `{0,85,170,255}`, tested against the actual chosen palette).

**Visual (simulator)** — for anything a passing test can't confirm:
- Icon/field pixel placement and sizing at actual screen scale.
- Color rendering on-device (or as close as the simulator gets) to rule out quantization shifts a unit test can't see.
- New sprite sheets: frame alignment (no sliding, matching the earlier `setClip` fix) and pacing/feel of new animations.
- Triggers that depend on real device state (battery level, time-of-day, notifications) — confirmed with temporarily-relaxed thresholds, then reverted, same pattern as the Phase 3 trigger-window shortening.

---

## Deferred

Surfaced by the in-depth review:
- Launcher icon is 24×24 but `fenix7s` wants 40×40 — it's being auto-upscaled and will look soft on-device (`-w` build warning). Cosmetic, independent of the phases above.

Continued from [coding-strategy.md](coding-strategy.md)'s own Deferred list:
- Developer key signing (needed only for device sideload / store submission, not simulator)
- Multi-language support (also re-confirmed live as a `-w` build warning during this review)
- Settings UI (background color, foreground color toggles) — background color specifically is picked up by Phase A above; foreground-color-specific settings remain deferred beyond that
- Performance profiling (only needed if frame drops are observed)

New from this pass:
- **Battery drain from animations — architectural reasoning documented now, on-device measurement deferred.** No dedicated battery/energy tool exists in the Connect IQ SDK; the closest available proxy is the CPU-time profiler (`File > View Profiler` in the simulator, or on-device via the `-k` compiler flag, producing a `.PRF` log in `GARMIN/APPS/LOGS`) — it measures function execution time, not energy directly. Our architecture already applies the single most impactful battery practice for watch faces: the animation timer only runs while the watch is actively awake (`onExitSleep`/`onEnterSleep`), not during sleep/AOD, where a typical wrist spends the large majority of the day.

  Within "awake," the more meaningful lever isn't the tick rates themselves but **redraw frequency while idle specifically**. The 400ms idle timer exists only to (a) animate the standing blink/bob and (b) count down to the next random trick, and every tick triggers a full-screen `requestUpdate()` — clock, date, dog, steps, battery all redraw, not just the sprite. The trick-clip tick rates (150ms lick, 120ms sit/stand, 130ms tail spin) matter much less since tricks are brief and infrequent (one every 8-20s at most, per Phase 3's tuning). If idle battery cost ever needs addressing, the actionable lever is here: either accept the blink/bob's redraw cost as the price of the idle animation, or drop the idle animation (a single static standing frame) and slow the idle tick to something far coarser — its only remaining job would be the trick-trigger countdown, which doesn't need sub-second precision. Sprite resource size (frame count in the bitmap itself) is explicitly *not* a lever here — the resource is tiny either way (a few KB difference at most) and loads once in `onLayout`, regardless of frame count; trimming a sprite's frame count without also changing the tick rate driving its redraws saves nothing.

  A real, ground-truth answer still needs actual on-device battery-life testing (installed vs. a stock watch face, compared over a day or more) — deferred until physical device sideloading is actually working, or another test device is available.
- Second dog breed (unscoped)
- Anything requiring a background service (e.g. a literal push-notification-content trigger, which would need the `Background` permission and a `ServiceDelegate` — bigger lift than the `Complications` notification-count proxy, not pursued unless the proxy proves insufficient)
- **Per-device-generation feature support, in general** — explore this as its own future pass rather than special-casing it per feature as we go. First concrete example: the native on-device watch face editor (`<watchface-config>` resource, `WatchFaceDelegate.onTap()`/`setSelectedComplication()`, field choices expressed as `Complications.COMPLICATION_TYPE_*`) is available on fēnix 8 and newer only (`doc/docs/Core_Topics/Editing_Watch_Faces_On_Device.html` in the SDK) — our `fenix8solar47mm` target could use it for a native tap-to-edit field picker instead of the Settings-menu approach Phase A uses uniformly. Not pursued now, both to keep Phase A's implementation single-path (per Phase 0's goal of reducing fan-out) and because `fenix7spro` (no native editor) is the stated primary target device. Likely more such generation-gated features exist (older devices lacking APIs Phase A/B assume, newer devices offering nicer alternatives) — worth a dedicated compatibility pass later rather than discovering them one at a time.
- **Composable sit/stand transitions — flagged tension, not resolved.** Sit-down and stand-up currently exist only as two clips embedded inside one compound trick (`mTricks[1]`), not as independently reusable primitives. If a future trick wants to "go sit, do something, stand back up," it would currently have to duplicate those clip definitions into its own list rather than composing shared "transition to sitting"/"transition to standing" building blocks. Worth flagging as possible unnecessary complication: building a generic composable sub-state system is a real design fork, and speculative before a second sit-originating trick is actually proposed (no known future trick needs it yet). The likely simpler alternative, if/when one is: bake the full desired sequence into one purpose-built sprite sheet (more art, same trick-table shape we already have) rather than adding a code-level composition layer — matches how tricks are already added today (one self-contained data entry) instead of introducing shared/reusable sub-sequences. Revisit only when a concrete second sit-originating trick is actually on the table.

---

## Before publishing

Checklist items that only matter at the point of actually publishing to the Connect IQ Store — nothing here blocks any development phase, but neither should get forgotten when that day comes.

- **Font Awesome attribution.** Free-tier icons require attribution (CC BY 4.0 for the icons, SIL OFL 1.1 for the fonts, MIT for the code — see the README's "Icons" section for the source). Font Awesome's own guidance assumes a served web asset that carries its embedded license comment along with it; a compiled `.prg` doesn't preserve that, so this needs an explicit credit line added to the Connect IQ Store listing description at publish time — a repo-only credit (already added to the README) isn't sufficient on its own once the app is actually distributed.
- **Developer key signing** — already tracked in Deferred above (continued from `coding-strategy.md`), flagged here too since it's the other concrete publish-time blocker, not just a someday item.
