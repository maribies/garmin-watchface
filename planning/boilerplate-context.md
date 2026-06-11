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
