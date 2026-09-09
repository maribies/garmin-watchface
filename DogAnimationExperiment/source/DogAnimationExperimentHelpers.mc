import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Weather;

// Pure, stateless helpers pulled out of DogAnimationExperimentView.mc so
// they're testable without touching private view state, and so the view
// file itself stays focused on drawing/lifecycle/data-fetching. Monkey C
// compiles every file under source/ into one namespace (no imports needed
// between them), so this split is purely organizational.

// Of the 9 candidate fields, at most this many are shown at once (3 rows x
// 2 columns) — see assignFieldPositions.
const MAX_VISIBLE_FIELDS = 6;

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
