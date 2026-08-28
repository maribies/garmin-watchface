# Boilerplate Context: DogAnimationExperiment

## Project Setup
- **App type**: `watchface`, API level 5.2.0 minimum
- **Target devices**: fenix7pro, fenix7pronowifi, fenix7s, fenix7spro, fenix8solar47mm
- **Screen**: 260×260px round display
- **SDK**: Connect IQ 9.1.0, Monkey C language

## Source Files
| File | Purpose |
|------|---------|
| `DogAnimationExperimentApp.mc` | Entry point, extends `Application.AppBase`, returns the WatchFace view |
| `DogAnimationExperimentView.mc` | Main watchface, extends `WatchUi.WatchFace` — all drawing and logic lives here |
| `DogAnimationExperimentBackground.mc` | A `Drawable` that clears the screen each frame |

## Lifecycle Hooks (in View)
| Hook | When it fires | Our use |
|------|--------------|---------|
| `onLayout(dc)` | Once on load | Load bitmap resources into memory |
| `onShow()` | View comes to foreground | — |
| `onUpdate(dc)` | Every second, or on `requestUpdate()` | Draw everything — time, stats, dog frame |
| `onHide()` | View leaves screen | Free resources |
| `onExitSleep()` | User raises wrist | Start animation timer |
| `onEnterSleep()` | Watch goes to sleep mode | Stop animation timer, revert to 1fps updates |

## Current State
- Layout is XML-driven (`resources/layouts/layout.xml`): a `Background` drawable + centered `TimeLabel` text
- `onUpdate` reads clock time and sets the label text
- No custom drawing, no stats, no animation

## Key APIs Available at 5.2.0
- `System.getClockTime()` — hours, minutes, seconds
- `System.getSystemStats()` — battery percentage
- `ActivityMonitor.getInfo()` — step count
- `System.getDeviceSettings()` — date, 12/24h preference
- `Toybox.Timer` — repeating timer for animation
- `WatchUi.requestUpdate()` — triggers an `onUpdate` call
- `WatchUi.loadResource(Rez.Drawables.X)` — loads a PNG bitmap resource
- `dc.drawBitmap(x, y, bitmap)` — draws a loaded bitmap at screen coordinates

## Drawing Approach Decision
For anything beyond simple text, the XML layout is abandoned in favor of direct `dc` drawing in `onUpdate`. This gives full control over layering: background → dog sprite → info overlays.

## Refinement-strategy API findings 
| Data / trigger | API | Permission | Notes |
|---|---|---|---|
| Steps, step goal, move bar level | `ActivityMonitor.Info` (already in use) | none | `moveBarLevel` vs `ActivityMonitor.MOVE_BAR_LEVEL_MAX` (5) is the actual move-alert threshold |
| Battery % | `System.getSystemStats().battery` (already in use) | none | |
| Heart rate | `ActivityMonitor.getHeartRateHistory(period, newestFirst)` | none | Simpler than `Complications` for this specific field — same module we already import, full example in Garmin's own docs. `Toybox.Sensor` (live) and `Toybox.SensorHistory` are **not** available to Watch Face apps at all — don't use those. In scope both as a Phase A field and (implement-vs-defer TBD right before building it) Phase B's heart-rate-triggered lick — refresh cadence for the field deferred to Phase A implementation, see note below |
| Resting heart rate | `UserProfile.Profile.restingHeartRate` / `.averageRestingHeartRate` | `UserProfile` | |
| Sleep / wake time | `UserProfile.Profile.sleepTime` / `.wakeTime` | `UserProfile` | These are the user's **configured habitual** times, not a live "about to sleep" prediction — good enough for a "near bedtime" trigger, just not literally real-time |
| Body battery | `Complications.COMPLICATION_TYPE_BODY_BATTERY` | `ComplicationSubscriber` | No `ActivityMonitor`/`UserProfile` path exists for this |
| Notification count (proxy for "message received") | `Complications.COMPLICATION_TYPE_NOTIFICATION_COUNT` | `ComplicationSubscriber` | Not a literal "new message" event — track the count and fire on any increase |
| Weather | `Toybox.Weather.CurrentConditions`, `.getDailyForecast()` | none | Returns null until the phone has synced weather data — needs a fallback display, not a hard requirement on connectivity per se. Refresh cadence decided below |
| Activity-alert-triggered spin | ~~`Toybox.ActivityPrompts`~~ | — | Dead end: that module is about a Data Field taking over audio/TTS during a *tracked activity*, restricted to Data Field/Glance app types. Not the same thing as a move alert (see move bar level above) |

`Complications` subscription pattern (for body battery / notification count):
```
Complications.subscribeToUpdates(new Complications.Id(Complications.COMPLICATION_TYPE_BODY_BATTERY));
Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
// in the callback:
var value = Complications.getComplication(id).value; // Number or null
```

**Subscription lifecycle — investigate before implementing:** `subscribeToUpdates` is push-based (the system calls our callback on change), not a poll loop — no timer needed for refresh itself. Scope subscriptions to the same awake/asleep lifecycle as the trick timer and bitmap loading (subscribe in `onShow`/`onExitSleep`, `unsubscribeFromAllUpdates()` in `onHide`/`onEnterSleep`), so nothing stays subscribed while asleep. Open questions to resolve just before implementation, not now:
- Does `getComplication(id)` return a value without an active subscription (usable for an immediate initial paint), or only after `subscribeToUpdates` — and even then, only once the first change event has fired? Determines whether a field can show real data on `onShow` or has to show a placeholder until the first change.
- Since Phase A's fields are user-configurable, the set of subscribed complications changes when Settings change mid-use — confirm the settings-changed callback (`Application.AppBase.onSettingsChanged()` or similar) and re-subscribe/unsubscribe there, not just on view show/hide.
- `subscribeToUpdates()` returns a `Boolean` — confirm what causes `false` (unsupported type on device vs. permission not granted vs. something else) and design the field's fallback display for that case, not just for a null `value`.

**Heart rate refresh cadence — decision deferred to Phase A implementation.** Direction to consider, not a final call: only refresh while the watch is actively being looked at (the same awake-only lifecycle as the trick timer/bitmaps/`Complications` subscriptions — `onExitSleep`/`onShow` to `onEnterSleep`/`onHide` — not continuously in the background), which is likely close to how the native heart-rate widget already behaves and should be good enough here. And only call `getHeartRateHistory()` at all if heart rate is one of the fields the user has actually selected to display — no point checking a field nobody chose to show. Exact interval while awake (every `onUpdate`? a slower dedicated cadence?) left for Phase A.

**Weather refresh cadence — decided:** `getCurrentConditions()`/`getDailyForecast()`/`getHourlyForecast()` all read the device's local cache — calling them doesn't itself trigger a network fetch, so checking more often isn't a battery cost the way subscribing to a live sensor would be (the actual phone-sync cadence is controlled by the OS, not us). So this is a *display freshness* decision, not a battery one: refresh the shown value at specific times of day rather than continuously, timed to when a Garmin wearer is actually likely to care — before a probable workout or commute. Compare current time against last-checked time inside the existing `onUpdate` (no dedicated `Timer` needed): check near `UserProfile.wakeTime`, midday (~12:00), and early evening (~17:00-18:00, exact anchor TBD at implementation). Use `CurrentConditions.temperature`/`.condition` for "right now," and `getDailyForecast()[0]` (`.condition`/`.highTemperature`/`.lowTemperature`/`.precipitationChance`) for a whole-day summary — Garmin already computes one representative condition per day for `DailyForecast`, matching the "single icon for the day" behavior from the 10-day forecast UI, so there's no need to average hourly readings ourselves.

**Color note carried over from Phase 1:** `fenix7s`/`fenix7spro` are `ARGB2222` — 4 levels per channel (`0, 85, 170, 255`). Any new background shade must land each channel on one of those four values or it'll shift color the way our gray shifted to yellow. Verify new palette entries the same way we verified the sprite gray (inspect actual pixel RGB, don't eyeball it).
