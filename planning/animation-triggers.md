# Animation Triggers

Reference for manual testing: every animation state, what fires it, and its current status. Update this alongside `refinement-strategy.md` as Phase B items land.

## Implemented

| Animation | Trigger | Duration | Notes |
|---|---|---|---|
| Idle (rest, bob, blink) | Default state — plays whenever no trick is active | Loops every 4 frames (`FRAME_ORDER = [0,1,0,2]`) at `IDLE_TICK_MS` (400ms/frame) | Always running in `STATE_IDLE`; resumes from rest (`FRAME_ORDER[0]`) after sleep. |
| Random trick (lick / tail-spin / sploot-rear) | Idle timer expires after a random delay | Delay: `MIN_TRICK_DELAY_TICKS`-`MAX_TRICK_DELAY_TICKS` idle ticks (currently 10-25 ticks = 4-10s) | Trick chosen uniformly at random (`pickTrickIndex`, equal odds across all tricks in `mTricks`) — not selectable individually. |
| — Lick | (one of the above) | 11 frames @ 150ms ≈ 1.65s | |
| — Tail spin | (one of the above) | 9 frames @ 130ms ≈ 1.17s | |
| — Sploot (rear view) | (one of the above) | 10 frames @ 150ms ≈ 1.5s | Replaced sit-down/stand-up in the pool. Pacing not yet confirmed live in the simulator. |
| Sploot (front view) | Battery ≤ `LOW_BATTERY_THRESHOLD_PERCENT` (20%, tentative), checked once per idle tick | 8 frames @ 150ms ≈ 1.2s | Only fires from idle, not mid-trick. Not part of the random pool — reached directly via `SPLOOT_FRONT_TRICK_INDEX`. Fires once per `onShow()` (`mLowBatteryTrickShown`), not once per low-battery *tick* — won't repeat until the next hide/show cycle even if battery stays low. Easiest trigger to test live: set battery % directly in the simulator. |
| Sleep (rest pose, frozen) | Device enters low-power/always-on display mode (`onEnterSleep`) | N/A — static | Stops the animation timer; resets to `STATE_IDLE` at the rest frame. |
| Resume from sleep | Device exits low-power mode (`onExitSleep`) | — | Calls `enterIdle()`, restarting the idle timer fresh (new random trick delay). |

**Also worth knowing while testing:** any hide/show cycle (backgrounding via a notification, widget glance, menu — not just sleep) also calls `enterIdle()` via `onShow()`, so the idle countdown resets whenever the watch face comes back to the foreground, not just after sleep.

## Planned (Phase B — not yet implemented)

| Animation | Trigger (candidate) | Notes |
|---|---|---|
| Feet tappies | Added to the random trick pool, same mechanism as existing tricks | Sheet on disk: `corgi-foot-taps-sheet.png`, 5 frames. |
| Move-alert | `moveBarLevel` reaches `MOVE_BAR_LEVEL_MAX` | Lower priority. Reuses an existing/new animation (tail spin, or foot-taps once built) rather than a dedicated sheet. |
| Heart-rate-triggered lick | A recent `getHeartRateHistory()` sample notably exceeds `UserProfile.restingHeartRate` | Reuses the existing lick animation. Implement-vs-defer decision deliberately deferred to right before building it (see `refinement-strategy.md`). |
