import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Application.Properties;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;
import Toybox.Weather;

// All corgi sprite sheets use 120x120 frames.
const FRAME_SIZE = 120;

// Standing idle play order: rest, bob-down, rest, blink-closed (see planning/sprite-recipe.md)
const FRAME_ORDER = [0, 1, 0, 2];
const IDLE_TICK_MS = 400;

// Shared by the sit-down and stand-up clips below (the compound sit/stand trick).
const STAND_TICK_MS = 120;

// Random trick trigger window, counted in idle ticks (8-20s at IDLE_TICK_MS).
const MIN_TRICK_DELAY_TICKS = 20;
const MAX_TRICK_DELAY_TICKS = 50;

// Sentinel for "not currently playing a trick." Valid trick states are
// indices into mTricks (0..mTricks.size()-1), built once bitmaps are loaded.
const STATE_IDLE = -1;

// Icon sizes as registered in drawables.xml (aspect-correct, ~20px tall).
const BATTERY_ICON_WIDTH = 25;
const BATTERY_ICON_HEIGHT = 20;

// Configurable fields, in fixed evaluation order: steps, heart rate,
// weather, body battery, calories, notifications, floors climbed,
// intensity minutes, distance. Widths match each icon's native scaleX in
// drawables.xml (all natively scaleY=20 tall) — drawn smaller at runtime
// per FIELD_ICON_SCALE, see drawField. Index 2 (weather) is a placeholder —
// its icon is condition-dependent, looked up from mWeatherIcons instead,
// see drawFields.
const FIELD_ICON_WIDTHS = [23, 20, 23, 20, 18, 20, 23, 18, 18];
const FIELD_ICON_HEIGHT = 20;
const FIELD_INDEX_WEATHER = 2;

// Icons are drawn slightly smaller than their native size (via
// drawScaledBitmap) so they read as a subordinate accent next to the value
// rather than competing with it for attention.
const FIELD_ICON_SCALE = 0.8;

// Vertical gap between an icon and its value, stacked tightly.
const FIELD_ICON_TEXT_GAP = 2;

// Margin kept between a field and the watch's actual round edge (see
// chordHalfWidthAt) so content doesn't crowd the bezel.
const FIELD_EDGE_MARGIN = 8;

// Of the 9 candidate fields, at most this many are shown at once (3 rows x
// 2 columns) — see assignFieldPositions.
const MAX_VISIBLE_FIELDS = 6;

// Pulled out of the view so it's testable without touching private view state.
function advanceOrderIndex(current as Number) as Number {
    return (current + 1) % FRAME_ORDER.size();
}

// Maps a raw random value to a trick delay within [MIN_TRICK_DELAY_TICKS, MAX_TRICK_DELAY_TICKS].
function ticksFromRandom(raw as Number) as Number {
    var span = MAX_TRICK_DELAY_TICKS - MIN_TRICK_DELAY_TICKS + 1;
    return MIN_TRICK_DELAY_TICKS + (raw % span);
}

// Maps a raw random value to which trick (index into mTricks) plays next.
function pickTrickIndex(raw as Number, trickCount as Number) as Number {
    return raw % trickCount;
}

// Maps a battery percentage to which battery icon to show: 0=full,
// 1=three-quarters, 2=half, 3=quarter, 4=empty (indices into mBatteryIcons).
function pickBatteryIconIndex(percent as Number) as Number {
    if (percent > 75) {
        return 0;
    } else if (percent > 50) {
        return 1;
    } else if (percent > 25) {
        return 2;
    } else if (percent > 10) {
        return 3;
    }
    return 4;
}

// True if every R/G/B channel of a 24-bit color is one of {0x00, 0x55, 0xAA,
// 0xFF} — the 4 levels ARGB2222 displays (fenix7s/fenix7spro) actually
// render. A channel outside that set gets silently shifted to the nearest
// one at render time, which is what turned our sprite gray yellow in Phase 1.
function isArgb2222Safe(color as Number) as Boolean {
    var safeLevels = [0x00, 0x55, 0xAA, 0xFF];
    var r = (color >> 16) & 0xFF;
    var g = (color >> 8) & 0xFF;
    var b = color & 0xFF;
    return safeLevels.indexOf(r) != -1 && safeLevels.indexOf(g) != -1 && safeLevels.indexOf(b) != -1;
}

// Steps a single channel value down one level in the ARGB2222-safe ladder
// (0xFF -> 0xAA -> 0x55 -> 0x00, floor at 0x00).
function stepDownChannel(channel as Number) as Number {
    if (channel >= 0xFF) {
        return 0xAA;
    } else if (channel >= 0xAA) {
        return 0x55;
    }
    return 0x00;
}

// Darkens a color by stepping each R/G/B channel down one level in the
// ARGB2222-safe ladder, staying safe by construction. Used to derive
// secondary text color from the selected background — a tint of the same
// hue rather than a fixed gray that clashes with whichever color is picked.
function darkerTint(color as Number) as Number {
    var r = stepDownChannel((color >> 16) & 0xFF);
    var g = stepDownChannel((color >> 8) & 0xFF);
    var b = stepDownChannel(color & 0xFF);
    return (r << 16) | (g << 8) | b;
}

// Formats a field's numeric value for display, or "--" if unavailable (no
// sensor reading yet, feature unsupported on this device, etc).
function formatFieldValue(value as Number or Null, suffix as String) as String {
    if (value == null) {
        return "--";
    }
    return value.toString() + suffix;
}

// Formats a step count: raw below 100,000 (its narrow column can't fit 6
// digits), abbreviated to the nearest thousand at or above it, prefixed
// with "+" since every bucket is a floor, not an exact count (100000-100999
// -> "+100k", 101000-101999 -> "+101k", 200000-200999 -> "+200k") — the "+"
// applies uniformly rather than just to the first bucket, since "101k" is
// just as much a rounded-down approximation as "100k" is.
function formatSteps(steps as Number or Null) as String {
    if (steps == null) {
        return "--";
    }
    if (steps < 100000) {
        return steps.toString();
    }
    return "+" + (steps / 1000).toString() + "k";
}

// Converts a Celsius reading to the requested display unit and rounds to a
// whole number for display, or "--" if the reading is unavailable.
function formatTemperature(celsiusValue as Float or Null, useStatute as Boolean) as String {
    if (celsiusValue == null) {
        return "--";
    }
    var displayValue = celsiusValue;
    if (useStatute) {
        displayValue = (celsiusValue * 9.0 / 5.0) + 32.0;
    }
    return displayValue.toNumber().toString();
}

// Formats a hi/lo temperature pair as "hi/lo", each side independently
// falling back to "--" if unavailable.
function formatTemperatureRange(highCelsius as Float or Null, lowCelsius as Float or Null, useStatute as Boolean) as String {
    return formatTemperature(highCelsius, useStatute) + "/" + formatTemperature(lowCelsius, useStatute);
}

// Y-coordinate where the time text begins (top of the time+date block).
// Shared by drawTimeDate (to draw it) and drawFields (so field rows know
// where the available vertical band ends without overlapping it).
function timeBlockTopY(height as Number, pad as Number) as Number {
    var dateHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_XTINY);
    var timeHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_LARGE);
    return height - pad - dateHeight - timeHeight;
}

// Half-width of the round screen's visible chord at a given y (distance
// from vertical/horizontal center — every currently supported device is a
// round, square-pixel-buffer display, so radius == cx == cy). Lets fields
// be positioned relative to the watch's actual edge rather than the dog
// sprite. Returns 0 once y is at or past the very top/bottom of the circle.
function chordHalfWidthAt(y as Number, cx as Number, cy as Number) as Number {
    var dy = y - cy;
    if (dy < 0) {
        dy = -dy;
    }
    if (dy >= cx) {
        return 0;
    }
    return Math.sqrt((cx * cx) - (dy * dy)).toNumber();
}

// Maps which fields are enabled (fixed evaluation order — see
// FIELD_ICON_WIDTHS' comment) to position indices 0..5 in fill order:
// bottom-left, bottom-right, middle-left, middle-right, top-left,
// top-right — the face grows upward as more fields are turned on, staying
// balanced regardless of which specific fields are enabled. Returns an
// Array the same length as `enabled`; each entry is a position index, or
// null if that field is off (or all MAX_VISIBLE_FIELDS slots are already
// filled by earlier fields in evaluation order).
function assignFieldPositions(enabled as Array<Boolean>) as Array {
    var positions = new [enabled.size()];
    var nextPosition = 0;
    for (var i = 0; i < enabled.size(); i += 1) {
        if (enabled[i] && nextPosition < MAX_VISIBLE_FIELDS) {
            positions[i] = nextPosition;
            nextPosition += 1;
        } else {
            positions[i] = null;
        }
    }
    return positions;
}

// Converts a distance in centimeters to the device's configured unit
// (kilometers or miles) and formats to one decimal place, or "--" if
// unavailable.
function formatDistance(centimeters as Number or Null, useStatute as Boolean) as String {
    if (centimeters == null) {
        return "--";
    }
    var displayValue = centimeters / 100000.0; // cm -> km
    if (useStatute) {
        displayValue = centimeters / 160934.4; // cm -> miles
    }
    var tenths = (displayValue * 10 + 0.5).toNumber();
    var whole = tenths / 10;
    var frac = tenths % 10;
    return whole.toString() + "." + frac.toString();
}

// Maps a Weather.Condition value to which weather icon family to show:
// clear-family -> sun, partly cloudy -> cloud+sun, cloudy family -> cloud,
// rain family -> cloud+rain, thunderstorm family -> cloud+bolt, snow/wintry
// family -> snowflake. Anything else (windy, fog, hazy, mist, dust,
// tornado, etc.) or no reading at all (condition == null) falls back to a
// generic thermometer rather than trying to cover every one of the ~35
// Weather.Condition values with a dedicated icon.
function weatherIconKey(condition as Number or Null) as Symbol {
    if (condition == Weather.CONDITION_CLEAR || condition == Weather.CONDITION_PARTLY_CLEAR || condition == Weather.CONDITION_MOSTLY_CLEAR) {
        return :sun;
    }
    if (condition == Weather.CONDITION_PARTLY_CLOUDY) {
        return :cloudSun;
    }
    if (condition == Weather.CONDITION_MOSTLY_CLOUDY || condition == Weather.CONDITION_CLOUDY) {
        return :cloud;
    }
    if (condition == Weather.CONDITION_RAIN || condition == Weather.CONDITION_LIGHT_RAIN || condition == Weather.CONDITION_HEAVY_RAIN
        || condition == Weather.CONDITION_SCATTERED_SHOWERS || condition == Weather.CONDITION_LIGHT_SHOWERS
        || condition == Weather.CONDITION_SHOWERS || condition == Weather.CONDITION_HEAVY_SHOWERS
        || condition == Weather.CONDITION_CHANCE_OF_SHOWERS || condition == Weather.CONDITION_DRIZZLE
        || condition == Weather.CONDITION_UNKNOWN_PRECIPITATION) {
        return :cloudRain;
    }
    if (condition == Weather.CONDITION_THUNDERSTORMS || condition == Weather.CONDITION_SCATTERED_THUNDERSTORMS
        || condition == Weather.CONDITION_CHANCE_OF_THUNDERSTORMS) {
        return :cloudBolt;
    }
    if (condition == Weather.CONDITION_SNOW || condition == Weather.CONDITION_LIGHT_SNOW || condition == Weather.CONDITION_HEAVY_SNOW
        || condition == Weather.CONDITION_WINTRY_MIX || condition == Weather.CONDITION_LIGHT_RAIN_SNOW
        || condition == Weather.CONDITION_HEAVY_RAIN_SNOW || condition == Weather.CONDITION_RAIN_SNOW
        || condition == Weather.CONDITION_HAIL) {
        return :snowflake;
    }
    return :thermometer;
}

// One tick of progress through a trick's clip sequence, as [nextClipIndex,
// nextClipFrame]. clips only needs each entry's :frameCount for this. If
// nextClipIndex >= clips.size(), the trick is complete — the caller is
// responsible for calling enterIdle() (timer reconfig + re-rolled trick
// delay) rather than applying the returned frame directly in that case.
function nextClipProgress(clipIndex as Number, clipFrame as Number, clips as Array<Dictionary>) as Array<Number> {
    var next = clipFrame + 1;
    if (next >= clips[clipIndex][:frameCount]) {
        return [clipIndex + 1, 0];
    }
    return [clipIndex, next];
}

class DogAnimationExperimentView extends WatchUi.WatchFace {

    private var mStandingBitmap = null;
    private var mBatteryIcons as Array or Null = null; // [full, threeQuarters, half, quarter, empty]

    // Configurable-field icons, aligned with FIELD_ICON_WIDTHS' order:
    // [steps, heart rate, weather, body battery, calories, notifications,
    // floors, intensity minutes, distance]. Weather's slot is unused (null)
    // — its icon is condition-dependent, see mWeatherIcons.
    private var mFieldIcons as Array or Null = null;

    // Weather icon variants, keyed by weatherIconKey()'s result. Each entry
    // is {:icon, :width} since the icons aren't all the same width.
    private var mWeatherIcons as Dictionary or Null = null;

    // Each trick is an Array of clips ({:bitmap, :startFrame, :frameCount,
    // :tickMs, :repeat}), played in order. Adding a trick means adding one
    // entry here — nothing else needs touching to wire it into the random
    // pool, the timer, or drawing.
    private var mTricks as Array<Array<Dictionary> > or Null = null;

    private var mAnimTimer = null;
    private var mState = STATE_IDLE;
    private var mOrderIndex = 0; // idle only: index into FRAME_ORDER
    private var mClipIndex = 0; // trick only: which clip within mTricks[mState]
    private var mClipFrame = 0; // trick only: 0-based frame progress within the current clip
    private var mTicksUntilTrick = MIN_TRICK_DELAY_TICKS;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        mStandingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStanding);
        mFieldIcons = [
            WatchUi.loadResource(Rez.Drawables.IconShoePrints),
            WatchUi.loadResource(Rez.Drawables.IconHeart),
            null,
            WatchUi.loadResource(Rez.Drawables.IconGauge),
            WatchUi.loadResource(Rez.Drawables.IconFire),
            WatchUi.loadResource(Rez.Drawables.IconMessage),
            WatchUi.loadResource(Rez.Drawables.IconStairs),
            WatchUi.loadResource(Rez.Drawables.IconStopwatch),
            WatchUi.loadResource(Rez.Drawables.IconPersonRunning),
        ];
        mWeatherIcons = {
            :sun => { :icon => WatchUi.loadResource(Rez.Drawables.IconSun), :width => 23 },
            :cloudSun => { :icon => WatchUi.loadResource(Rez.Drawables.IconCloudSun), :width => 25 },
            :cloud => { :icon => WatchUi.loadResource(Rez.Drawables.IconCloud), :width => 23 },
            :cloudRain => { :icon => WatchUi.loadResource(Rez.Drawables.IconCloudRain), :width => 20 },
            :cloudBolt => { :icon => WatchUi.loadResource(Rez.Drawables.IconCloudBolt), :width => 20 },
            :snowflake => { :icon => WatchUi.loadResource(Rez.Drawables.IconSnowflake), :width => 20 },
            :thermometer => { :icon => WatchUi.loadResource(Rez.Drawables.IconTemperatureHalf), :width => 13 },
        };
        mBatteryIcons = [
            WatchUi.loadResource(Rez.Drawables.IconBatteryFull),
            WatchUi.loadResource(Rez.Drawables.IconBatteryThreeQuarters),
            WatchUi.loadResource(Rez.Drawables.IconBatteryHalf),
            WatchUi.loadResource(Rez.Drawables.IconBatteryQuarter),
            WatchUi.loadResource(Rez.Drawables.IconBatteryEmpty),
        ];
        var lickingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiLicking);
        var sitToStandBitmap = WatchUi.loadResource(Rez.Drawables.CorgiSitToStand);
        var standToSitBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStandToSit);
        var tailSpinBitmap = WatchUi.loadResource(Rez.Drawables.CorgiTailSpin);

        mTricks = [
            // Lick: 11 frames at 150ms
            [
                { :bitmap => lickingBitmap, :startFrame => 0, :frameCount => 11, :tickMs => 150, :repeat => true },
            ],
            // Sit down (5 frames) -> hold seated (1 frame, 1s) -> stand back up (5 frames)
            [
                { :bitmap => standToSitBitmap, :startFrame => 0, :frameCount => 5, :tickMs => STAND_TICK_MS, :repeat => true },
                { :bitmap => standToSitBitmap, :startFrame => 4, :frameCount => 1, :tickMs => 1000, :repeat => false },
                { :bitmap => sitToStandBitmap, :startFrame => 0, :frameCount => 5, :tickMs => STAND_TICK_MS, :repeat => true },
            ],
            // Tail spin: 9 frames at 130ms
            [
                { :bitmap => tailSpinBitmap, :startFrame => 0, :frameCount => 9, :tickMs => 130, :repeat => true },
            ],
        ];
    }

    function onShow() as Void {
    }

    // Idle (standing, blinking) -> random trick -> idle ...
    function onAnimTimer() as Void {
        if (mState == STATE_IDLE) {
            mOrderIndex = advanceOrderIndex(mOrderIndex);
            mTicksUntilTrick -= 1;
            if (mTicksUntilTrick <= 0) {
                startRandomTrick();
            }
        } else {
            var clips = mTricks[mState];
            var step = nextClipProgress(mClipIndex, mClipFrame, clips);
            if (step[0] >= clips.size()) {
                enterIdle();
            } else {
                var clipChanged = step[0] != mClipIndex;
                mClipIndex = step[0];
                mClipFrame = step[1];
                if (clipChanged) {
                    configureTimerForClip(clips[mClipIndex]);
                }
            }
        }

        WatchUi.requestUpdate();
    }

    function startRandomTrick() as Void {
        mState = pickTrickIndex(Math.rand(), mTricks.size());
        mClipIndex = 0;
        mClipFrame = 0;
        configureTimerForClip(mTricks[mState][0]);
    }

    function enterIdle() as Void {
        mState = STATE_IDLE;
        mOrderIndex = 0;
        mTicksUntilTrick = ticksFromRandom(Math.rand());
        configureIdleTimer();
    }

    function configureIdleTimer() as Void {
        if (mAnimTimer == null) {
            mAnimTimer = new Timer.Timer();
        }
        mAnimTimer.start(method(:onAnimTimer), IDLE_TICK_MS, true);
    }

    function configureTimerForClip(clip as Dictionary) as Void {
        if (mAnimTimer == null) {
            mAnimTimer = new Timer.Timer();
        }
        mAnimTimer.start(method(:onAnimTimer), clip[:tickMs], clip[:repeat]);
    }

    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var cx = width / 2;
        var height = dc.getHeight();
        var cy = height / 2;
        var pad = 10;

        // Background — user-configurable via Settings (Properties.BackgroundColor).
        var backgroundColor = Properties.getValue("BackgroundColor") as Number;
        dc.setColor(backgroundColor, backgroundColor);
        dc.clear();

        // Subtext (steps count, date) is derived from the background so it
        // reads as a matching tint of whichever color is picked, instead of
        // a fixed gray that can clash. Time stays plain black.
        var subtextColor = darkerTint(backgroundColor);

        // Battery — icon, top center.
        drawBattery(dc, cx, pad);

        // Dog sprite — current animation frame, roughly centered (nudged up
        // slightly to leave breathing room for the time/date block below).
        drawDog(dc, cx, cy);

        // Configurable fields — up to 4, positioned relative to the watch's
        // actual round edge rather than the dog sprite. Position is derived
        // from which are enabled, not individually chosen: the first
        // enabled field takes left-upper, the second right-upper, the
        // third left-lower, the fourth right-lower.
        drawFields(dc, cx, cy, height, pad, subtextColor);

        // Time + date — bottom center, time larger/prominent, date small
        // beneath it, whole block anchored to the bottom padding.
        drawTimeDate(dc, cx, height, pad, subtextColor);
    }

    // Battery icon, level-selected, centered horizontally at the given y.
    private function drawBattery(dc as Dc, cx as Number, y as Number) as Void {
        var stats = System.getSystemStats();
        var battery = stats.battery.toNumber();
        var batteryIcon = mBatteryIcons[pickBatteryIconIndex(battery)];
        if (batteryIcon != null) {
            dc.drawBitmap(cx - (BATTERY_ICON_WIDTH / 2), y, batteryIcon as WatchUi.BitmapResource);
        }
    }

    // Draws the current animation frame, centered around (cx, cy) and nudged
    // up slightly to leave room for the time/date block below. Clips to one
    // frame's window and blits the whole sheet shifted left, rather than
    // relying on drawBitmap2's :bitmapX/:bitmapWidth crop.
    private function drawDog(dc as Dc, cx as Number, cy as Number) as Void {
        var dogBitmap = mStandingBitmap;
        var frameToDraw = FRAME_ORDER[mOrderIndex];
        if (mState != STATE_IDLE) {
            var clip = mTricks[mState][mClipIndex];
            dogBitmap = clip[:bitmap];
            frameToDraw = (clip[:startFrame] as Number) + mClipFrame;
        }

        var dogX = cx - (FRAME_SIZE / 2);
        var dogY = cy - (FRAME_SIZE / 2) - 10;
        if (dogBitmap != null) {
            dc.setClip(dogX, dogY, FRAME_SIZE, FRAME_SIZE);
            dc.drawBitmap(dogX - (frameToDraw * FRAME_SIZE), dogY, dogBitmap as WatchUi.BitmapResource);
            dc.clearClip();
        }
    }

    // Draws up to 6 configurable fields (of 9 candidates — steps, heart
    // rate, weather, body battery, calories, notifications, floors,
    // intensity minutes, distance): two columns, each anchored to the
    // watch's actual round edge (via chordHalfWidthAt) rather than the dog
    // sprite, growing inward toward center; up to three rows, stacked
    // together just above the time block with a small padding between them
    // (rather than spread out) since that's more room than a compact
    // icon-above-value field actually needs. Because columns are edge-based
    // and rows are independent of the sprite, a wide value (weather's hi/lo
    // pair, or steps before it's abbreviated) can visually overlap the dog
    // — nothing here clips against the sprite. Position is derived from
    // which fields are enabled (assignFieldPositions), filling bottom-left,
    // bottom-right, middle-left, middle-right, top-left, top-right in that
    // order so the face grows upward and stays balanced regardless of
    // which specific fields are on.
    private function drawFields(dc as Dc, cx as Number, cy as Number, height as Number, pad as Number, subtextColor as Number) as Void {
        var enabled = [
            Properties.getValue("ShowSteps") as Boolean,
            Properties.getValue("ShowHeartRate") as Boolean,
            Properties.getValue("ShowWeather") as Boolean,
            Properties.getValue("ShowBodyBattery") as Boolean,
            Properties.getValue("ShowCalories") as Boolean,
            Properties.getValue("ShowNotifications") as Boolean,
            Properties.getValue("ShowFloors") as Boolean,
            Properties.getValue("ShowIntensityMinutes") as Boolean,
            Properties.getValue("ShowDistance") as Boolean,
        ];
        var conditions = currentWeatherConditions();
        var weatherCondition = null;
        if (conditions != null) {
            weatherCondition = conditions.condition;
        }
        var weatherIcon = mWeatherIcons[weatherIconKey(weatherCondition)];

        var values = [
            stepsValue(),
            heartRateValue(),
            weatherValueText(conditions),
            bodyBatteryValue(),
            caloriesValue(),
            notificationsValue(),
            floorsValue(),
            intensityMinutesValue(),
            distanceValue(),
        ];
        var positions = assignFieldPositions(enabled);

        var textHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_XTINY);
        var scaledIconHeight = (FIELD_ICON_HEIGHT * FIELD_ICON_SCALE).toNumber();
        var stackedRowHeight = scaledIconHeight + FIELD_ICON_TEXT_GAP + textHeight;

        var bottomGap = 4; // breathing room from the time block below
        var rowPadding = 6; // between adjacent field rows
        var bottomRowY = timeBlockTopY(height, pad) - bottomGap - stackedRowHeight;
        var middleRowY = bottomRowY - rowPadding - stackedRowHeight;
        var topRowY = middleRowY - rowPadding - stackedRowHeight;

        // Sampled at each row's vertical center — close enough for a field
        // a couple dozen pixels tall, without needing per-pixel precision.
        var bottomHalfWidth = chordHalfWidthAt(bottomRowY + (stackedRowHeight / 2), cx, cy);
        var middleHalfWidth = chordHalfWidthAt(middleRowY + (stackedRowHeight / 2), cx, cy);
        var topHalfWidth = chordHalfWidthAt(topRowY + (stackedRowHeight / 2), cx, cy);

        // [edgeX, alignToRightEdge, rowY] per position: 0=bottom-left,
        // 1=bottom-right, 2=middle-left, 3=middle-right, 4=top-left,
        // 5=top-right. Left-column fields start at the edge and grow
        // rightward (alignToRightEdge false); right-column fields end at
        // the edge and grow leftward (true).
        var positionCoords = [
            [cx - bottomHalfWidth + FIELD_EDGE_MARGIN, false, bottomRowY],
            [cx + bottomHalfWidth - FIELD_EDGE_MARGIN, true, bottomRowY],
            [cx - middleHalfWidth + FIELD_EDGE_MARGIN, false, middleRowY],
            [cx + middleHalfWidth - FIELD_EDGE_MARGIN, true, middleRowY],
            [cx - topHalfWidth + FIELD_EDGE_MARGIN, false, topRowY],
            [cx + topHalfWidth - FIELD_EDGE_MARGIN, true, topRowY],
        ];

        for (var i = 0; i < enabled.size(); i += 1) {
            var positionIndex = positions[i];
            if (positionIndex != null) {
                var coords = positionCoords[positionIndex];
                var icon = mFieldIcons[i];
                var iconWidth = FIELD_ICON_WIDTHS[i];
                if (i == FIELD_INDEX_WEATHER) {
                    icon = weatherIcon[:icon];
                    iconWidth = weatherIcon[:width];
                }
                drawField(dc, coords[0], coords[1], coords[2], icon, iconWidth, values[i], subtextColor);
            }
        }
    }

    // One field: icon above value, stacked tightly (FIELD_ICON_TEXT_GAP).
    // edgeX is either the shared left edge (alignToRightEdge false, for
    // left-column fields — icon and value both start at the watch edge) or
    // the shared right edge (true, for right-column fields — both end at
    // the edge). Icon and value are NOT centered relative to each other —
    // each is only as wide as it needs to be, so a narrow icon sits
    // noticeably off-center under/over a wider value (or vice versa)
    // instead of the pair reserving room for whichever is wider on both
    // sides — more compact than centering them would be.
    private function drawField(dc as Dc, edgeX as Number, alignToRightEdge as Boolean, rowY as Number, icon as Object or Null, iconWidth as Number, valueText as String, subtextColor as Number) as Void {
        var font = Graphics.FONT_SYSTEM_XTINY;
        var textWidth = dc.getTextWidthInPixels(valueText, font);
        var scaledIconWidth = (iconWidth * FIELD_ICON_SCALE).toNumber();
        var scaledIconHeight = (FIELD_ICON_HEIGHT * FIELD_ICON_SCALE).toNumber();

        var iconX = edgeX;
        var textX = edgeX;
        if (alignToRightEdge) {
            iconX = edgeX - scaledIconWidth;
            textX = edgeX - textWidth;
        }
        var iconY = rowY;
        var textY = rowY + scaledIconHeight + FIELD_ICON_TEXT_GAP;

        if (icon != null) {
            dc.drawScaledBitmap(iconX, iconY, scaledIconWidth, scaledIconHeight, icon as WatchUi.BitmapResource);
        }
        dc.setColor(subtextColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(textX, textY, font, valueText, Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function stepsValue() as String {
        var activityInfo = ActivityMonitor.getInfo();
        var steps = null;
        if (activityInfo != null) {
            steps = activityInfo.steps;
        }
        return formatSteps(steps);
    }

    private function heartRateValue() as String {
        var history = ActivityMonitor.getHeartRateHistory(1, true);
        var sample = history.next();
        var heartRate = null;
        if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
            heartRate = sample.heartRate;
        }
        return formatFieldValue(heartRate, "");
    }

    private function currentWeatherConditions() as Weather.CurrentConditions or Null {
        if (!(Toybox has :Weather) || !(Toybox.Weather has :getCurrentConditions)) {
            return null;
        }
        return Weather.getCurrentConditions();
    }

    private function weatherValueText(conditions as Weather.CurrentConditions or Null) as String {
        if (conditions == null) {
            return "--/--";
        }
        var useStatute = System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE;
        return formatTemperatureRange(conditions.highTemperature, conditions.lowTemperature, useStatute);
    }

    private function bodyBatteryValue() as String {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getBodyBatteryHistory)) {
            return "--";
        }
        var iterator = SensorHistory.getBodyBatteryHistory({});
        var sample = iterator.next();
        var level = null;
        if (sample != null && sample.data != null) {
            // .data is typed Number or Float — comes back as a Float here,
            // and Float.toString() prints full decimal precision ("55.000000"),
            // not the plain "55" a percentage should show.
            level = sample.data.toNumber();
        }
        return formatFieldValue(level, "");
    }

    private function caloriesValue() as String {
        var activityInfo = ActivityMonitor.getInfo();
        var calories = null;
        if (activityInfo != null) {
            calories = activityInfo.calories;
        }
        return formatFieldValue(calories, "");
    }

    private function notificationsValue() as String {
        return formatFieldValue(System.getDeviceSettings().notificationCount, "");
    }

    private function floorsValue() as String {
        var activityInfo = ActivityMonitor.getInfo();
        var floors = null;
        if (activityInfo != null) {
            floors = activityInfo.floorsClimbed;
        }
        return formatFieldValue(floors, "");
    }

    private function intensityMinutesValue() as String {
        var activityInfo = ActivityMonitor.getInfo();
        var minutes = null;
        if (activityInfo != null && activityInfo.activeMinutesWeek != null) {
            minutes = activityInfo.activeMinutesWeek.total;
        }
        return formatFieldValue(minutes, "");
    }

    private function distanceValue() as String {
        var activityInfo = ActivityMonitor.getInfo();
        var distance = null;
        if (activityInfo != null) {
            distance = activityInfo.distance;
        }
        var useStatute = System.getDeviceSettings().distanceUnits == System.UNIT_STATUTE;
        return formatDistance(distance, useStatute);
    }

    // Time (large, prominent) above date (small), bottom center, whole block
    // anchored to the bottom padding.
    private function drawTimeDate(dc as Dc, cx as Number, height as Number, pad as Number, dateColor as Number) as Void {
        var dateHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_XTINY);
        var dateY = height - pad - dateHeight;
        var timeY = timeBlockTopY(height, pad);

        var clockTime = System.getClockTime();
        var hours = clockTime.hour;
        var useMilitaryFormat = Properties.getValue("UseMilitaryFormat") as Boolean;
        if (!useMilitaryFormat) {
            if (hours == 0) {
                hours = 12;
            } else if (hours > 12) {
                hours = hours - 12;
            }
        }
        var timeString = Lang.format("$1$:$2$", [hours, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, timeY, Graphics.FONT_SYSTEM_LARGE, timeString, Graphics.TEXT_JUSTIFY_CENTER);

        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateString = Lang.format("$1$ $2$ $3$", [today.day_of_week, today.month, today.day]);
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dateY, Graphics.FONT_SYSTEM_XTINY, dateString, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function onHide() as Void {
        mStandingBitmap = null;
        mFieldIcons = null;
        mWeatherIcons = null;
        mBatteryIcons = null;
        mTricks = null;
    }

    function onExitSleep() as Void {
        enterIdle();
    }

    function onEnterSleep() as Void {
        if (mAnimTimer != null) {
            mAnimTimer.stop();
        }
        mState = STATE_IDLE;
        mOrderIndex = 0;
    }

}
