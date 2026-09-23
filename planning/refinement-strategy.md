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

1. ~~**Icons.**~~ **Done.** All icons sourced as SVG directly from Font Awesome Free, registered in `drawables.xml` under `resources/drawables/icons/` — no PNG conversion step needed. Battery has 5 charge-level variants (full/three-quarters/half/quarter/empty) selected from `System.getSystemStats().battery`; every configurable field (see item 3) has its own icon, including 7 weather-condition variants. `ARGB2222` safety hasn't been a problem in practice — icons are solid black, always safe.
2. ~~**Background colors.**~~ **Done.** Extended `resources/settings/properties.xml` + `settings.xml` (the `Properties_and_App_Settings` mechanism) with a 6-shade `BackgroundColor` list (red, blue, yellow, green, purple, orange), all `ARGB2222`-safe, read fresh every `onUpdate()`. **Decided:** time and icons stay fixed black; steps-count and date text derive a one-step-darker tint of the chosen background (`darkerTint()`, steps each R/G/B channel down one level in the safe ladder, safe by construction) rather than a fixed gray, so they read as a matching color per background instead of clashing. The dead `ForegroundColor` setting (never wired to anything) was removed rather than repurposed. Icon recoloring to match was investigated and declined for now: the SDK has no pixel-read/write or blend-mode API to recolor a rasterized bitmap at runtime, so the only real option is pre-baked per-background SVG variants (36 resources instead of 6) — feasible given the palette is fixed at 6 colors, but not worth the resource count for a secondary element right now. Revisit if icon/text mismatch becomes a real complaint.
3. ~~**Configurable data fields.**~~ **Done** (iterated live in the simulator across many rounds — see below for what's still outstanding). Same Settings-menu mechanism as background color, uniform across all supported devices (`fenix7pro`, `fenix7pronowifi`, `fenix7s`, `fenix7spro`, `fenix8solar47mm`) rather than branching for fēnix 8's native field editor — see Deferred. Battery moved to a fixed icon at top-center (no longer a selectable field); date+time stay fixed at bottom-center; dog stays centered.

   **9 candidate fields, up to 6 shown at once**, each an independent boolean Property (`ShowSteps`/`ShowHeartRate`/`ShowWeather`/`ShowBodyBattery`/`ShowCalories`/`ShowNotifications`/`ShowFloors`/`ShowIntensityMinutes`/`ShowDistance`) rather than per-slot pickers:
   - Steps (shoe icon, `ActivityMonitor.Info.steps`) — abbreviates at 100,000+ to `+Nk` (floor to the nearest thousand, e.g. `+101k`) so a large count never overflows its column.
   - Heart rate (heart icon) — reads `ActivityMonitor.getHeartRateHistory()`, not `Sensor.getInfo()`: the latter needs the `Sensor` permission, which for a watchface additionally requires `Background` (a bigger lift, explicitly avoided per Deferred below).
   - Weather (7 icon variants — sun/partly-cloudy-sun/cloud/cloud-rain/cloud-bolt/snowflake/thermometer-fallback, mapped from `Weather.Condition` by family) — hi/lo temperature from `Weather.getCurrentConditions()`, converted to the device's configured unit (`temperatureUnits`, always returned in Celsius regardless of device setting — confirmed in the SDK docs, so the conversion is load-bearing, not defensive).
   - Body battery (gauge icon — Garmin's own body-battery icon is proprietary/not offered free anywhere, and Font Awesome has nothing equivalent, so a speedometer/dial reads as "a measured level" without colliding with any other icon on the face) — reads `SensorHistory.getBodyBatteryHistory()` (needs the `SensorHistory` manifest permission). Its `SensorSample.data` comes back as a `Float`, not `Number` — `Float.toString()` prints full decimal precision (`"55.000000"`), so it's explicitly cast via `.toNumber()` before formatting.
   - Calories (fire icon, `.calories`), notifications (message icon, `System.getDeviceSettings().notificationCount`), floors climbed (stairs icon, `.floorsClimbed`), intensity minutes (stopwatch icon, `.activeMinutesWeek.total` — Garmin's own weekly rolling total, not a daily figure, matching how the real feature works), distance (running-person icon, `.distance` in centimeters, converted via `distanceUnits` and formatted to one decimal place).

   All fall back to `"--"` (or `"--/--"` for weather's hi/lo pair) when unavailable, each API-gated by a `has` check before calling where the API isn't universally available.

   **Position:** generic fill order, not fixed per field identity — `assignFieldPositions()` walks the 9 fields in a fixed evaluation order and assigns the Nth *enabled* field to the Nth of 6 positions, filling bottom-left → bottom-right → middle-left → middle-right → top-left → top-right, so the face grows upward and stays balanced regardless of which specific fields are on. (This supersedes an earlier version that pinned steps/weather to the bottom row specifically because they were "the wide ones" — with 9 candidates there's no longer a clean way to say which are reliably wide, so that per-identity rule was dropped in favor of pure fill-order.) A 7th+ enabled field beyond the 6-slot cap simply doesn't render.

   **Layout is edge-based, not sprite-based**, on both axes — a real pivot mid-Phase-A: columns are anchored to the watch's actual round edge (`chordHalfWidthAt()`, the circle's usable half-width — `sqrt(r² - dy²)` — at a given row, since every supported device is round with a square pixel buffer) rather than to the dog sprite's bounding box; rows are stacked together just above the time block with small padding, rather than spread between the battery icon and the time block. Nothing clips a field against the sprite, so a wide value (weather's hi/lo pair, unabbreviated steps) can visually overlap the dog — accepted tradeoff, not yet a real complaint.

   **Each field renders icon-above-value**, tightly stacked (`FIELD_ICON_TEXT_GAP`), with the icon and value sharing one anchor edge (both left-aligned for left-column fields, both right-aligned for right-column) rather than centered relative to each other — since they're rarely the same width, this reads as intentionally off-center and only needs as much room as the wider of the two, not their sum. Icons draw at 80% of native size (`FIELD_ICON_SCALE`, via `drawScaledBitmap`) so they read as a subordinate accent next to the value.

   A `TEMPORARY` hardcoded heart-rate/body-battery override used mid-development to check layout against worst-case text width has been reverted — both read live data again.

   **Post-completion review** consolidated `FIELD_ICON_WIDTHS`/`mFieldIcons`/inline property-key strings into one `mFieldDefs` list (propertyKey/icon/width/value-provider per field, instead of four arrays that had to stay in sync by convention), replaced `weatherIconKey()`'s if/`||` chain with a Dictionary lookup, and switched `positionCoords` from positional tuples to named Dictionary fields. Caught a real crash along the way: **`method(:symbolName)` can't bind to a `private` instance method in this SDK** — referencing 8 `private function` value-providers via `method()` in `mFieldDefs` crashed `onLayout()` at runtime ("Failed invoking `<symbol>`"), invisible to the unit tests since none of them exercise `onLayout()`. Fixed by dropping `private` from those methods. Worth remembering for any future `method()` callback.
4. Second dog breed stays deferred, unscoped, per the original notes' "eventually."

**Verification:** Each new icon/color/field checked live in the simulator — pixel alignment, `ARGB2222` color fidelity, and (for weather) the fallback state when `CurrentConditions` is null.

**Phase A is complete.** All three scoped items (icons, background colors, configurable data fields) are done and verified live; the second dog breed was never in scope for this phase. Clear to start Phase B.

**Post-launch fix:** a real on-device crash (decoded from the watch's own `GARMIN/APPS/LOGS/CIQ_LOG.BAK`, via the SDK's `debug.xml` pc-to-line map — see "Framework lifecycle contract" below) reverted the watch face to a fallback after some background/foreground cycles. Root cause: resource caches (`mBatteryIcons`, `mFieldDefs`, `mWeatherIcons`, `mStandingBitmap`, `mTricks`) were populated once in `onLayout()` and freed in `onHide()`, but never reloaded in `onShow()` — backwards from `View`'s own documented contract (`onShow()`: "Resources should be loaded"; `onHide()`: "Resources should be freed"). Any hide/show cycle short of full sleep (a notification, a widget glance) left those fields `null` until the next crash. The animation timer had the same gap — stopped only on `onEnterSleep()`, not `onHide()`, so it kept firing into the now-null `mTricks` even while backgrounded. Fixed by moving resource population into `onShow()` and stopping/restarting `mAnimTimer` symmetrically with `onHide()`/`onShow()`. This pattern traces all the way back to Garmin's own SDK-generated `onHide()` boilerplate comment ("freeing resources from memory") — every field added since just extended that block without anyone reloading it on the show side.

---

## Phase B — New animated behaviors

**Goal:** More triggers wired into the existing random-trick state machine, using the sprite sheets already on disk.

Assets already present (frame counts inferred from sheet width ÷ 120px, same as the existing sheets — frame order and per-frame timing still need deciding the same way we did for tail spin: inspect actual pixel alignment, propose a play order, confirm live):

| Sheet | Frames |
|---|---|
| `corgi-foot-taps-sheet.png` | 5 |
| `corgi-sploot-front-sheet.png` | 8 |
| `corgi-sploot-rear-sheet.png` | 10 |

0. ~~**Sit-stand removed from the random trick pool, replaced by sploot (rear view).**~~ **Done.** Not a new trigger — a swap within the existing roster (was lick/sit-stand/tail-spin, now lick/tail-spin/sploot-rear), decided once both sploot views turned out to need different treatment (see item 2). The `corgi-sit-to-stand-sheet.png`/`corgi-stand-to-sit-sheet.png` sheets and their drawables.xml entries were deleted as part of this, since nothing else used them.
1. **Feet tappies.** **Done.** See `animation-triggers.md` for the implementation.
2. **Laying down (sploot).** **Done** — both rear (random pool) and front (conditional, low battery) views. See `animation-triggers.md` for the implementation. Activity-goal-reached, step-goal-reached and near-bedtime are candidates for additional conditional triggers.
3. **Move-alert trigger.** **Done.** Reuses tail spin. See `animation-triggers.md` for the implementation.
4. **High-stress-triggered lick.** **Done.** Implemented against stress level instead of heart-rate-vs-resting (decided as more directly meaningful than an HR comparison). Reuses the existing lick animation. See `animation-triggers.md` for the implementation.

**Verification:** Each new trigger confirmed live — both that the condition actually fires (may need temporarily-relaxed thresholds the way we shortened the trick-trigger window in Phase 3, to test without waiting for a real low-battery/bedtime moment) and that the animation renders correctly via the `setClip`+`drawBitmap` approach already proven for the existing sheets.

**Phase B is complete.** All four items done. Activity-goal-reached, step-goal-reached, and near-bedtime (noted under item 2) remain unscoped candidates for further conditional triggers, not blockers.

---

## Phase C -- allow for selection between 2 dog animations

The choices will be the corgi or an aussie. The choice will be made in the settings. Hopefully we can choose to only load the necessary resource files. All the animations and triggers will remain the same.

---

---

## Phase D -- add additional watch/version support.

I would like to extend support for friends to be able to use, if possible.
- vivioactive 6
Let's support as many as possible. First research and confirm with the API and docs before committing.


---

## Testing, as we go

**Framework lifecycle contract.** Add this as an explicit review step: any override of a method whose name and calling convention are dictated by the platform (`onShow`, `onHide`, `onLayout`, `onEnterSleep`, `onExitSleep`, etc. — not our own helpers) gets checked against that method's actual doc comment before being approved, not just judged on whether the code "looks reasonable." The SDK ships this doc text locally in `bin/api.debug.xml` (each `<functionEntry>`'s `<documentation>` CDATA block) — no need to guess or rely on memory of the API. The `onShow()`/`onHide()` load/free bug above is exactly the failure mode this would have caught: every prior review (Java-engineer pass, DevOps pass) read our code in isolation and reasoned about it as self-consistent, without ever pulling the framework's own contract for the lifecycle methods it touched.

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
- ~~Settings UI (background color, foreground color toggles).~~ Resolved by Phase A above — background color and the 9 field toggles are both done via the Settings mechanism; the originally-envisioned `ForegroundColor` setting was found dead (never wired to anything) and removed outright rather than built out.
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
