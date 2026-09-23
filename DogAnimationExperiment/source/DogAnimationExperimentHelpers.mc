import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Weather;

// Pure, stateless helpers for DogAnimationExperimentView.mc.

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

function isLowBattery(percent as Number, thresholdPercent as Number) as Boolean {
    return percent <= thresholdPercent;
}

// True if every R/G/B channel is one of {0x00, 0x55, 0xAA, 0xFF} — the 4
// levels ARGB2222 displays actually render; anything else gets silently
// shifted at render time.
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

// Darkens a color one step per channel, staying ARGB2222-safe by
// construction. Used to derive text color from the background.
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

// Formats a step count: raw below 100,000, else abbreviated to the nearest
// thousand with a "+" (100000-100999 -> "+100k", every bucket is a floor).
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

// Half-width of the round screen's visible chord at a given y. Assumes a
// round, square-pixel-buffer display (radius == cx == cy), true of every
// currently supported device. Returns 0 past the top/bottom of the circle.
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

// Maps enabled fields to position indices 0..5 (bottom-left, bottom-right,
// middle-left, middle-right, top-left, top-right), densely packed in fixed
// evaluation order — not sticky: toggling one field can shift others'
// positions. Null for a disabled field or once all slots are filled.
function assignFieldPositions(enabled as Array<Boolean>) as Array<Number or Null> {
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

// Weather.Condition -> icon family. Not exhaustive (~26 of ~35 conditions
// covered) — anything missing falls back to :thermometer in weatherIconKey.
const WEATHER_ICON_KEYS_BY_CONDITION = {
    Weather.CONDITION_CLEAR => :sun,
    Weather.CONDITION_PARTLY_CLEAR => :sun,
    Weather.CONDITION_MOSTLY_CLEAR => :sun,
    Weather.CONDITION_PARTLY_CLOUDY => :cloudSun,
    Weather.CONDITION_MOSTLY_CLOUDY => :cloud,
    Weather.CONDITION_CLOUDY => :cloud,
    Weather.CONDITION_RAIN => :cloudRain,
    Weather.CONDITION_LIGHT_RAIN => :cloudRain,
    Weather.CONDITION_HEAVY_RAIN => :cloudRain,
    Weather.CONDITION_SCATTERED_SHOWERS => :cloudRain,
    Weather.CONDITION_LIGHT_SHOWERS => :cloudRain,
    Weather.CONDITION_SHOWERS => :cloudRain,
    Weather.CONDITION_HEAVY_SHOWERS => :cloudRain,
    Weather.CONDITION_CHANCE_OF_SHOWERS => :cloudRain,
    Weather.CONDITION_DRIZZLE => :cloudRain,
    Weather.CONDITION_UNKNOWN_PRECIPITATION => :cloudRain,
    Weather.CONDITION_THUNDERSTORMS => :cloudBolt,
    Weather.CONDITION_SCATTERED_THUNDERSTORMS => :cloudBolt,
    Weather.CONDITION_CHANCE_OF_THUNDERSTORMS => :cloudBolt,
    Weather.CONDITION_SNOW => :snowflake,
    Weather.CONDITION_LIGHT_SNOW => :snowflake,
    Weather.CONDITION_HEAVY_SNOW => :snowflake,
    Weather.CONDITION_WINTRY_MIX => :snowflake,
    Weather.CONDITION_LIGHT_RAIN_SNOW => :snowflake,
    Weather.CONDITION_HEAVY_RAIN_SNOW => :snowflake,
    Weather.CONDITION_RAIN_SNOW => :snowflake,
    Weather.CONDITION_HAIL => :snowflake,
};

function weatherIconKey(condition as Number or Null) as Symbol {
    if (condition == null) {
        return :thermometer;
    }
    var key = WEATHER_ICON_KEYS_BY_CONDITION[condition];
    if (key == null) {
        return :thermometer;
    }
    return key;
}

// One tick of progress through a trick's clip sequence, as [nextClipIndex,
// nextClipFrame]. If nextClipIndex >= clips.size(), the trick is complete
// and the caller should call enterIdle() instead of using the frame.
function nextClipProgress(clipIndex as Number, clipFrame as Number, clips as Array<Dictionary>) as Array<Number> {
    var next = clipFrame + 1;
    if (next >= clips[clipIndex][:frameCount]) {
        return [clipIndex + 1, 0];
    }
    return [clipIndex, next];
}
