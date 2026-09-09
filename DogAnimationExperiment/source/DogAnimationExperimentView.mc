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

// Pure, stateless helpers (formatting, geometry, animation-state math) live
// in DogAnimationExperimentHelpers.mc — this file is drawing, lifecycle,
// and data-fetching only.

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
