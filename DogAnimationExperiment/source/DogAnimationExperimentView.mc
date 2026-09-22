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

// Sentinel for "not currently playing a trick" (valid states are indices
// into mTricks).
const STATE_IDLE = -1;

// Icon sizes as registered in drawables.xml (aspect-correct, ~20px tall).
const BATTERY_ICON_WIDTH = 25;

// Index into mFieldDefs. Weather's icon/width come from mWeatherIcons
// instead — see drawFields.
const FIELD_INDEX_WEATHER = 2;

const FIELD_ICON_HEIGHT = 20;

// Icons draw smaller than native size so they read as a subordinate accent
// next to the value.
const FIELD_ICON_SCALE = 0.8;

// Vertical gap between an icon and its value, stacked tightly.
const FIELD_ICON_TEXT_GAP = 2;

// Margin from the watch's round edge (see chordHalfWidthAt) so fields
// don't crowd the bezel.
const FIELD_EDGE_MARGIN = 8;

// Pure, stateless helpers live in DogAnimationExperimentHelpers.mc.

class DogAnimationExperimentView extends WatchUi.WatchFace {

    private var mStandingBitmap = null;
    private var mBatteryIcons as Array or Null = null; // [full, threeQuarters, half, quarter, empty]

    // The 9 configurable fields, in fixed evaluation order: steps, heart
    // rate, weather, body battery, calories, notifications, floors climbed,
    // intensity minutes, distance. Each entry: {:propertyKey, :icon,
    // :iconWidth, :valueFn}. Weather's :icon/:iconWidth are unused
    // (condition-dependent, see mWeatherIcons) and it has no :valueFn
    // (special-cased in drawFields since its value needs CurrentConditions).
    private var mFieldDefs as Array<Dictionary> or Null = null;

    // Weather icon variants, keyed by weatherIconKey()'s result. Each entry
    // is {:icon, :width} since the icons aren't all the same width.
    private var mWeatherIcons as Dictionary<Symbol, Dictionary> or Null = null;

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

    // Cached formatted date string, recomputed only when the hour changes
    // (see drawTimeDate).
    private var mCachedDateString as String or Null = null;
    private var mCachedDateHour as Number or Null = null;

    // Refreshed once per drawFields() call, read by multiple value-provider
    // methods so they don't each fetch the same data independently.
    private var mCurrentActivityInfo as ActivityMonitor.Info or Null = null;
    private var mCurrentDeviceSettings as System.DeviceSettings or Null = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
    }

    // Populated here, not onLayout() (which only runs once) -- onShow()/onHide()
    // fire on every foreground/background transition, per View's documented contract.
    function onShow() as Void {
        mStandingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStanding);
        mFieldDefs = [
            { :propertyKey => "ShowSteps", :icon => WatchUi.loadResource(Rez.Drawables.IconShoePrints), :iconWidth => 23, :valueFn => method(:stepsValue) },
            { :propertyKey => "ShowHeartRate", :icon => WatchUi.loadResource(Rez.Drawables.IconHeart), :iconWidth => 20, :valueFn => method(:heartRateValue) },
            { :propertyKey => "ShowWeather", :icon => null, :iconWidth => 0, :valueFn => null },
            { :propertyKey => "ShowBodyBattery", :icon => WatchUi.loadResource(Rez.Drawables.IconGauge), :iconWidth => 20, :valueFn => method(:bodyBatteryValue) },
            { :propertyKey => "ShowCalories", :icon => WatchUi.loadResource(Rez.Drawables.IconFire), :iconWidth => 18, :valueFn => method(:caloriesValue) },
            { :propertyKey => "ShowNotifications", :icon => WatchUi.loadResource(Rez.Drawables.IconMessage), :iconWidth => 20, :valueFn => method(:notificationsValue) },
            { :propertyKey => "ShowFloors", :icon => WatchUi.loadResource(Rez.Drawables.IconStairs), :iconWidth => 23, :valueFn => method(:floorsValue) },
            { :propertyKey => "ShowIntensityMinutes", :icon => WatchUi.loadResource(Rez.Drawables.IconStopwatch), :iconWidth => 18, :valueFn => method(:intensityMinutesValue) },
            { :propertyKey => "ShowDistance", :icon => WatchUi.loadResource(Rez.Drawables.IconPersonRunning), :iconWidth => 18, :valueFn => method(:distanceValue) },
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

        enterIdle();
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

        // Subtext tints to match the background instead of a fixed gray.
        var subtextColor = darkerTint(backgroundColor);

        // Battery — icon, top center.
        drawBattery(dc, cx, pad);

        // Dog sprite — current animation frame, roughly centered (nudged up
        // slightly to leave breathing room for the time/date block below).
        drawDog(dc, cx, cy);

        // Configurable fields — up to 6 of 9 candidates. See drawFields.
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

    // Draws up to 6 of the 9 configurable fields: two columns anchored to
    // the watch's round edge (chordHalfWidthAt), growing inward; up to
    // three rows stacked above the time block. Position comes from
    // assignFieldPositions, filling bottom-left/right, middle-left/right,
    // top-left/right in that order. Nothing clips against the dog sprite,
    // so a wide value can overlap it.
    private function drawFields(dc as Dc, cx as Number, cy as Number, height as Number, pad as Number, subtextColor as Number) as Void {
        // Fetched once per frame and read by the value-provider methods
        // below, rather than each of them calling these independently —
        // up to 5 fields share mCurrentActivityInfo, up to 3 share
        // mCurrentDeviceSettings.
        mCurrentActivityInfo = ActivityMonitor.getInfo();
        mCurrentDeviceSettings = System.getDeviceSettings();

        var enabled = new [mFieldDefs.size()];
        for (var i = 0; i < mFieldDefs.size(); i += 1) {
            enabled[i] = Properties.getValue(mFieldDefs[i][:propertyKey]) as Boolean;
        }
        var positions = assignFieldPositions(enabled);

        var textHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_XTINY);
        var scaledIconHeight = (FIELD_ICON_HEIGHT * FIELD_ICON_SCALE).toNumber();
        var stackedRowHeight = scaledIconHeight + FIELD_ICON_TEXT_GAP + textHeight;

        var bottomGap = 4; // breathing room from the time block below
        var rowPadding = 6; // between adjacent field rows
        var bottomRowY = timeBlockTopY(height, pad) - bottomGap - stackedRowHeight;
        var middleRowY = bottomRowY - rowPadding - stackedRowHeight;
        var topRowY = middleRowY - rowPadding - stackedRowHeight;

        // Sampled at each row's vertical center.
        var bottomHalfWidth = chordHalfWidthAt(bottomRowY + (stackedRowHeight / 2), cx, cy);
        var middleHalfWidth = chordHalfWidthAt(middleRowY + (stackedRowHeight / 2), cx, cy);
        var topHalfWidth = chordHalfWidthAt(topRowY + (stackedRowHeight / 2), cx, cy);

        // Index order: bottom-left, bottom-right, middle-left, middle-right,
        // top-left, top-right. alignToRightEdge false = grows rightward
        // from the edge; true = grows leftward.
        var positionCoords = [
            { :edgeX => cx - bottomHalfWidth + FIELD_EDGE_MARGIN, :alignToRightEdge => false, :rowY => bottomRowY },
            { :edgeX => cx + bottomHalfWidth - FIELD_EDGE_MARGIN, :alignToRightEdge => true, :rowY => bottomRowY },
            { :edgeX => cx - middleHalfWidth + FIELD_EDGE_MARGIN, :alignToRightEdge => false, :rowY => middleRowY },
            { :edgeX => cx + middleHalfWidth - FIELD_EDGE_MARGIN, :alignToRightEdge => true, :rowY => middleRowY },
            { :edgeX => cx - topHalfWidth + FIELD_EDGE_MARGIN, :alignToRightEdge => false, :rowY => topRowY },
            { :edgeX => cx + topHalfWidth - FIELD_EDGE_MARGIN, :alignToRightEdge => true, :rowY => topRowY },
        ];

        for (var i = 0; i < enabled.size(); i += 1) {
            var positionIndex = positions[i];
            if (positionIndex != null) {
                var coords = positionCoords[positionIndex];
                var def = mFieldDefs[i];
                var icon = def[:icon];
                var iconWidth = def[:iconWidth];
                var valueText;
                if (i == FIELD_INDEX_WEATHER) {
                    var conditions = currentWeatherConditions();
                    var weatherCondition = null;
                    if (conditions != null) {
                        weatherCondition = conditions.condition;
                    }
                    var weatherIcon = mWeatherIcons[weatherIconKey(weatherCondition)];
                    icon = weatherIcon[:icon];
                    iconWidth = weatherIcon[:width];
                    valueText = weatherValueText(conditions);
                } else {
                    valueText = def[:valueFn].invoke() as String;
                }
                drawField(dc, coords[:edgeX], coords[:alignToRightEdge], coords[:rowY], icon, iconWidth, valueText, subtextColor);
            }
        }
    }

    // One field: icon above value, stacked tightly, both anchored to edgeX
    // (icon and value are each their own width, not centered on each other).
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

    function stepsValue() as String {
        var steps = null;
        if (mCurrentActivityInfo != null) {
            steps = mCurrentActivityInfo.steps;
        }
        return formatSteps(steps);
    }

    function heartRateValue() as String {
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
        var useStatute = mCurrentDeviceSettings.temperatureUnits == System.UNIT_STATUTE;
        return formatTemperatureRange(conditions.highTemperature, conditions.lowTemperature, useStatute);
    }

    function bodyBatteryValue() as String {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getBodyBatteryHistory)) {
            return "--";
        }
        var iterator = SensorHistory.getBodyBatteryHistory({});
        var sample = iterator.next();
        var level = null;
        if (sample != null && sample.data != null) {
            // .data comes back as a Float; toString() on it prints
            // "55.000000" instead of "55" if not cast first.
            level = sample.data.toNumber();
        }
        return formatFieldValue(level, "");
    }

    function caloriesValue() as String {
        var calories = null;
        if (mCurrentActivityInfo != null) {
            calories = mCurrentActivityInfo.calories;
        }
        return formatFieldValue(calories, "");
    }

    function notificationsValue() as String {
        return formatFieldValue(mCurrentDeviceSettings.notificationCount, "");
    }

    function floorsValue() as String {
        var floors = null;
        if (mCurrentActivityInfo != null) {
            floors = mCurrentActivityInfo.floorsClimbed;
        }
        return formatFieldValue(floors, "");
    }

    function intensityMinutesValue() as String {
        var minutes = null;
        if (mCurrentActivityInfo != null && mCurrentActivityInfo.activeMinutesWeek != null) {
            minutes = mCurrentActivityInfo.activeMinutesWeek.total;
        }
        return formatFieldValue(minutes, "");
    }

    function distanceValue() as String {
        var distance = null;
        if (mCurrentActivityInfo != null) {
            distance = mCurrentActivityInfo.distance;
        }
        var useStatute = mCurrentDeviceSettings.distanceUnits == System.UNIT_STATUTE;
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

        // The date only changes once a day; Gregorian.info() does real
        // calendar math, so only redo it when the hour we already have on
        // hand has changed, rather than on every draw.
        if (mCachedDateString == null || clockTime.hour != mCachedDateHour) {
            var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            mCachedDateString = Lang.format("$1$ $2$ $3$", [today.day_of_week, today.month, today.day]);
            mCachedDateHour = clockTime.hour;
        }
        dc.setColor(dateColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dateY, Graphics.FONT_SYSTEM_XTINY, mCachedDateString, Graphics.TEXT_JUSTIFY_CENTER);
    }

    function onHide() as Void {
        if (mAnimTimer != null) {
            mAnimTimer.stop();
        }
        mStandingBitmap = null;
        mFieldDefs = null;
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
