# Animation Triggers

Reference for manual testing: every animation state, what fires it, and its current status. Update this alongside `refinement-strategy.md` as Phase B items land.

## Implemented

| Animation | Trigger | Duration | Notes |
|---|---|---|---|
| Idle (rest, bob, blink) | Default state — plays whenever no trick is active | Loops every 4 frames (`FRAME_ORDER = [0,1,0,2]`) at `IDLE_TICK_MS` (400ms/frame) | Always running in `STATE_IDLE`; resumes from rest (`FRAME_ORDER[0]`) after sleep. |
| Random trick (lick / tail-spin / sploot-rear / foot-taps) | Idle timer expires after a random delay | Delay: `MIN_TRICK_DELAY_TICKS`-`MAX_TRICK_DELAY_TICKS` idle ticks (currently 10-25 ticks = 4-10s) | Trick chosen uniformly at random (`pickTrickIndex`, equal odds across all tricks in `mTricks`) — not selectable individually. |
| — Lick | (one of the above) | 11 frames @ 150ms ≈ 1.65s | |
| — Tail spin | (one of the above) | 9 frames @ 130ms ≈ 1.17s | |
| — Sploot (rear view) | (one of the above) | 10 frames @ 150ms ≈ 1.5s | Replaced sit-down/stand-up in the pool. |
| — Foot taps | (one of the above) | 5 frames @ 130ms ≈ 0.65s | |
| Sploot (front view) | Battery ≤ `LOW_BATTERY_THRESHOLD_PERCENT` (20%) or `CRITICAL_BATTERY_THRESHOLD_PERCENT` (10%), checked once per idle tick | 8 frames @ 150ms ≈ 1.2s | Only fires from idle, not mid-trick. Not part of the random pool — reached via `mSplootFrontTrickIndex`, a fixed offset past the random-pool entries in `mTricks`. Same animation plays for both tiers: once at 20%, again as a second warning at 10%. Each tier fires once per `onShow()`, not once per tick — won't repeat until the next hide/show cycle even if battery stays low. Crossing straight past 20% to ≤10% in one tick plays it once, not twice (the 10% check also consumes the 20% tier). Verified live: fires at 20%, fires again at 10%. |
| Move-alert | `moveBarLevel` ≥ `MOVE_BAR_LEVEL_MAX` (5), checked once per idle tick | 9 frames @ 130ms ≈ 1.17s | Reuses tail spin's bitmap/clip. Same once-per-`onShow()` pattern as the battery tiers. |
| Sleep (rest pose, frozen) | Device enters low-power/always-on display mode (`onEnterSleep`) | N/A — static | Stops the animation timer; resets to `STATE_IDLE` at the rest frame. |
| Resume from sleep | Device exits low-power mode (`onExitSleep`) | — | Calls `enterIdle()`, restarting the idle timer fresh (new random trick delay). |

**Also worth knowing while testing:** any hide/show cycle (backgrounding via a notification, widget glance, menu — not just sleep) also calls `enterIdle()` via `onShow()`, so the idle countdown resets whenever the watch face comes back to the foreground, not just after sleep.
