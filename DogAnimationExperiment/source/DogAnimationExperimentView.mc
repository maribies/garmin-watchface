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

// Standing idle play order: rest, bob-down, rest, blink-closed (see planning/sprite-recipe.md)
const FRAME_ORDER = [0, 1, 0, 2];
const IDLE_TICK_MS = 400;

// Random trick trigger window, counted in idle ticks (4-10s at IDLE_TICK_MS).
const MIN_TRICK_DELAY_TICKS = 10;
const MAX_TRICK_DELAY_TICKS = 25;

// Two tiers, same animation replayed as a second warning.
const LOW_BATTERY_THRESHOLD_PERCENT = 20;
const CRITICAL_BATTERY_THRESHOLD_PERCENT = 10;

const HIGH_STRESS_THRESHOLD = 76;

// Conditional triggers in priority order, and the trick each plays.
const TRIGGER_ORDER = [:criticalBattery, :lowBattery, :moveAlert, :highStress];
const TRIGGER_TRICKS = {
    :criticalBattery => :splootFront,
    :lowBattery => :splootFront,
    :moveAlert => :moveAlert,
    :highStress => :lick,
};

// Matches the DogBreed listEntry values in settings.xml.
const DOG_BREED_CORGI = 0;
const DOG_BREED_AUSSIE = 1;

// Sentinel for "not currently playing a trick" (valid states are keys
// into mTricks).
const STATE_IDLE = null;

// Index into mFieldDefs. Weather's icon comes from mWeatherIcons
// instead — see drawFields.
const FIELD_INDEX_WEATHER = 2;

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
    // Frames are square and one sheet-height wide; set per breed load.
    private var mFrameSize = 0;
    private var mBatteryIcons as Array or Null = null; // [full, threeQuarters, half, quarter, empty]

    // The 9 configurable fields, in fixed evaluation order: steps, heart
    // rate, weather, body battery, calories, notifications, floors climbed,
    // intensity minutes, distance. Each entry: {:propertyKey, :icon,
    // :valueFn}. Weather's :icon is unused (condition-dependent, see
    // mWeatherIcons) and it has no :valueFn (special-cased in
    // refreshFieldCache since its value needs CurrentConditions).
    private var mFieldDefs as Array<Dictionary> or Null = null;

    // Weather icon variants, keyed by weatherIconKey()'s result.
    private var mWeatherIcons as Dictionary or Null = null;

    // Each trick is an Array of clips ({:bitmap, :startFrame, :frameCount,
    // :tickMs, :repeat}), played in order, keyed by name. mRandomTrickKeys
    // lists which keys the random pool draws from.
    private var mTricks as Dictionary<Symbol, Array<Dictionary> > or Null = null;
    private var mRandomTrickKeys as Array<Symbol> or Null = null;

    private var mAnimTimer = null;
    private var mState = STATE_IDLE;
    private var mOrderIndex = 0; // idle only: index into FRAME_ORDER
    private var mClipIndex = 0; // trick only: which clip within mTricks[mState]
    private var mClipFrame = 0; // trick only: 0-based frame progress within the current clip
    private var mTicksUntilTrick = MIN_TRICK_DELAY_TICKS;
    // Keyed by TRIGGER_ORDER; see stepTriggers.
    private var mTriggerArmed as Dictionary<Symbol, Boolean> = {};
    private var mIsAsleep = false;

    // Cached formatted date string, recomputed only when the hour changes
    // (see drawTimeDate).
    private var mCachedDateString as String or Null = null;
    private var mCachedDateHour as Number or Null = null;

    // Refreshed by refreshFieldCache(), read by multiple value-provider
    // methods so they don't each fetch the same data independently.
    private var mCurrentActivityInfo as ActivityMonitor.Info or Null = null;
    private var mCurrentDeviceSettings as System.DeviceSettings or Null = null;
    private var mStressLevel as Number or Null = null;

    private var mFieldCacheMinute as Number or Null = null;
    private var mBackgroundColor as Number = 0;
    private var mUseMilitaryFormat as Boolean = true;
    // Indexed like mFieldDefs: {:position, :icon, :text}, or null if not shown.
    private var mFieldRender as Array<Dictionary or Null> or Null = null;

    function initialize() {
        WatchFace.initialize();
        Math.srand(System.getTimer());
        for (var i = 0; i < TRIGGER_ORDER.size(); i += 1) {
            mTriggerArmed[TRIGGER_ORDER[i]] = true;
        }
    }

    function onLayout(dc as Dc) as Void {
    }

    // Populated here, not onLayout() (which only runs once) -- onShow()/onHide()
    // fire on every foreground/background transition, per View's documented contract.
    function onShow() as Void {
        loadBreedResources();
        mFieldDefs = [
            { :propertyKey => "ShowSteps", :icon => WatchUi.loadResource(Rez.Drawables.IconShoePrints), :valueFn => method(:stepsValue) },
            { :propertyKey => "ShowHeartRate", :icon => WatchUi.loadResource(Rez.Drawables.IconHeart), :valueFn => method(:heartRateValue) },
            { :propertyKey => "ShowWeather", :icon => null, :valueFn => null },
            { :propertyKey => "ShowBodyBattery", :icon => WatchUi.loadResource(Rez.Drawables.IconGauge), :valueFn => method(:bodyBatteryValue) },
            { :propertyKey => "ShowCalories", :icon => WatchUi.loadResource(Rez.Drawables.IconFire), :valueFn => method(:caloriesValue) },
            { :propertyKey => "ShowNotifications", :icon => WatchUi.loadResource(Rez.Drawables.IconMessage), :valueFn => method(:notificationsValue) },
            { :propertyKey => "ShowFloors", :icon => WatchUi.loadResource(Rez.Drawables.IconStairs), :valueFn => method(:floorsValue) },
            { :propertyKey => "ShowIntensityMinutes", :icon => WatchUi.loadResource(Rez.Drawables.IconStopwatch), :valueFn => method(:intensityMinutesValue) },
            { :propertyKey => "ShowDistance", :icon => WatchUi.loadResource(Rez.Drawables.IconPersonRunning), :valueFn => method(:distanceValue) },
        ];
        mWeatherIcons = {
            :sun => WatchUi.loadResource(Rez.Drawables.IconSun),
            :cloudSun => WatchUi.loadResource(Rez.Drawables.IconCloudSun),
            :cloud => WatchUi.loadResource(Rez.Drawables.IconCloud),
            :cloudRain => WatchUi.loadResource(Rez.Drawables.IconCloudRain),
            :cloudBolt => WatchUi.loadResource(Rez.Drawables.IconCloudBolt),
            :snowflake => WatchUi.loadResource(Rez.Drawables.IconSnowflake),
            :thermometer => WatchUi.loadResource(Rez.Drawables.IconTemperatureHalf),
        };
        mBatteryIcons = [
            WatchUi.loadResource(Rez.Drawables.IconBatteryFull),
            WatchUi.loadResource(Rez.Drawables.IconBatteryThreeQuarters),
            WatchUi.loadResource(Rez.Drawables.IconBatteryHalf),
            WatchUi.loadResource(Rez.Drawables.IconBatteryQuarter),
            WatchUi.loadResource(Rez.Drawables.IconBatteryEmpty),
        ];
        invalidateFieldCache();
        if (isLowPower()) {
            resetToRestPose();
        } else {
            enterIdle();
        }
    }

    private function isLowPower() as Boolean {
        var displayMode = null;
        if (System has :getDisplayMode) {
            displayMode = System.getDisplayMode();
        }
        return isLowPowerMode(displayMode, mIsAsleep);
    }

    private function resetToRestPose() as Void {
        mState = STATE_IDLE;
        mOrderIndex = 0;
    }

    function invalidateFieldCache() as Void {
        mFieldCacheMinute = null;
    }

    private function refreshFieldCache(minute as Number) as Void {
        mBackgroundColor = Properties.getValue("BackgroundColor") as Number;
        mUseMilitaryFormat = Properties.getValue("UseMilitaryFormat") as Boolean;
        mCurrentActivityInfo = ActivityMonitor.getInfo();
        mCurrentDeviceSettings = System.getDeviceSettings();
        mStressLevel = currentStressLevel();

        var enabled = new [mFieldDefs.size()];
        for (var i = 0; i < mFieldDefs.size(); i += 1) {
            enabled[i] = Properties.getValue(mFieldDefs[i][:propertyKey]) as Boolean;
        }
        var positions = assignFieldPositions(enabled);

        mFieldRender = new [mFieldDefs.size()];
        for (var i = 0; i < mFieldDefs.size(); i += 1) {
            if (positions[i] == null) {
                continue;
            }
            var def = mFieldDefs[i];
            var icon = def[:icon];
            var text;
            if (i == FIELD_INDEX_WEATHER) {
                var conditions = currentWeatherConditions();
                var weatherCondition = null;
                if (conditions != null) {
                    weatherCondition = conditions.condition;
                }
                icon = mWeatherIcons[weatherIconKey(weatherCondition)];
                text = weatherValueText(conditions);
            } else {
                text = def[:valueFn].invoke() as String;
            }
            mFieldRender[i] = { :position => positions[i], :icon => icon, :text => text };
        }
        mFieldCacheMinute = minute;
    }

    private function needsBurnInSafeFace() as Boolean {
        return mCurrentDeviceSettings.requiresBurnInProtection && isLowPower();
    }

    // Loads mStandingBitmap/mTricks/mRandomTrickKeys for the current
    // DogBreed setting. Never touches mAnimTimer.
    private function loadBreedResources() as Void {
        var standingRes = Rez.Drawables.CorgiStanding;
        var lickingRes = Rez.Drawables.CorgiLicking;
        var tailSpinRes = Rez.Drawables.CorgiTailSpin;
        var footTapsRes = Rez.Drawables.CorgiFootTaps;
        var splootRearRes = Rez.Drawables.CorgiSplootRear;
        var splootFrontRes = Rez.Drawables.CorgiSplootFront;
        if ((Properties.getValue("DogBreed") as Number) == DOG_BREED_AUSSIE) {
            standingRes = Rez.Drawables.AussieStanding;
            lickingRes = Rez.Drawables.AussieLicking;
            tailSpinRes = Rez.Drawables.AussieTailSpin;
            footTapsRes = Rez.Drawables.AussieFootTaps;
            splootRearRes = Rez.Drawables.AussieSplootRear;
            splootFrontRes = Rez.Drawables.AussieSplootFront;
        }

        mStandingBitmap = WatchUi.loadResource(standingRes);
        mFrameSize = (mStandingBitmap as WatchUi.BitmapResource).getHeight();
        var lickingBitmap = WatchUi.loadResource(lickingRes);
        var tailSpinBitmap = WatchUi.loadResource(tailSpinRes);
        var footTapsBitmap = WatchUi.loadResource(footTapsRes);
        var splootRearBitmap = WatchUi.loadResource(splootRearRes);
        var splootFrontBitmap = WatchUi.loadResource(splootFrontRes);

        mTricks = {
            :lick => [
                { :bitmap => lickingBitmap, :startFrame => 0, :frameCount => 11, :tickMs => 150, :repeat => true },
            ],
            :tailSpin => [
                { :bitmap => tailSpinBitmap, :startFrame => 0, :frameCount => 9, :tickMs => 130, :repeat => true },
            ],
            :splootRear => [
                { :bitmap => splootRearBitmap, :startFrame => 0, :frameCount => 10, :tickMs => 150, :repeat => true },
            ],
            :footTaps => [
                { :bitmap => footTapsBitmap, :startFrame => 0, :frameCount => 5, :tickMs => 130, :repeat => true },
            ],
            // Conditional -- low battery.
            :splootFront => [
                { :bitmap => splootFrontBitmap, :startFrame => 0, :frameCount => 8, :tickMs => 150, :repeat => true },
            ],
            // Conditional -- move alert. Reuses tail spin
            :moveAlert => [
                { :bitmap => tailSpinBitmap, :startFrame => 0, :frameCount => 9, :tickMs => 130, :repeat => true },
            ],
        };
        mRandomTrickKeys = [:lick, :tailSpin, :splootRear, :footTaps];
    }

    function reloadBreed() as Void {
        loadBreedResources();
        WatchUi.requestUpdate();
    }

    // Idle (standing, blinking) -> random trick -> idle ...
    function onAnimTimer() as Void {
        if (mState == STATE_IDLE) {
            var stats = System.getSystemStats();
            var battery = stats.battery.toNumber();
            var moveBarLevel = null;
            if (mCurrentActivityInfo != null) {
                moveBarLevel = mCurrentActivityInfo.moveBarLevel;
            }
            var active = {
                :criticalBattery => shouldAlertLowBattery(battery, CRITICAL_BATTERY_THRESHOLD_PERCENT, stats.charging),
                :lowBattery => shouldAlertLowBattery(battery, LOW_BATTERY_THRESHOLD_PERCENT, stats.charging),
                :moveAlert => moveBarLevel != null && isMoveBarMax(moveBarLevel, ActivityMonitor.MOVE_BAR_LEVEL_MAX),
                :highStress => mStressLevel != null && isHighStress(mStressLevel, HIGH_STRESS_THRESHOLD),
            };
            var fired = stepTriggers(TRIGGER_ORDER, TRIGGER_TRICKS, mTriggerArmed, active);
            if (fired != null) {
                startTrick(TRIGGER_TRICKS[fired]);
            } else {
                mOrderIndex = advanceOrderIndex(mOrderIndex);
                mTicksUntilTrick -= 1;
                if (mTicksUntilTrick <= 0) {
                    startRandomTrick();
                }
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
        var idx = pickTrickIndex(Math.rand(), mRandomTrickKeys.size());
        startTrick(mRandomTrickKeys[idx]);
    }

    function randomTrickPoolSize() as Number {
        return mRandomTrickKeys.size();
    }

    function startTrick(key as Symbol) as Void {
        mState = key;
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

        var minute = System.getClockTime().min;
        if (fieldCacheNeedsRefresh(mFieldCacheMinute, minute)) {
            refreshFieldCache(minute);
        }

        if (needsBurnInSafeFace()) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            drawTimeDate(dc, cx, height, pad, mBackgroundColor, darkerTint(mBackgroundColor));
            return;
        }

        dc.setColor(mBackgroundColor, mBackgroundColor);
        dc.clear();

        // Subtext tints to match the background instead of a fixed gray.
        var subtextColor = darkerTint(mBackgroundColor);

        // Battery — icon, top center.
        drawBattery(dc, cx, pad);

        // Dog sprite — current animation frame, roughly centered (nudged up
        // slightly to leave breathing room for the time/date block below).
        drawDog(dc, cx, cy);

        // Configurable fields — up to 6 of 9 candidates. See drawFields.
        drawFields(dc, cx, cy, height, pad, subtextColor);

        // Time + date — bottom center, time larger/prominent, date small
        // beneath it, whole block anchored to the bottom padding.
        drawTimeDate(dc, cx, height, pad, Graphics.COLOR_BLACK, subtextColor);
    }

    // Battery icon, level-selected, centered horizontally at the given y.
    private function drawBattery(dc as Dc, cx as Number, y as Number) as Void {
        var stats = System.getSystemStats();
        var battery = stats.battery.toNumber();
        var batteryIcon = mBatteryIcons[pickBatteryIconIndex(battery)];
        if (batteryIcon != null) {
            var icon = batteryIcon as WatchUi.BitmapResource;
            dc.drawBitmap(cx - (icon.getWidth() / 2), y, icon);
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

        var dogX = cx - (mFrameSize / 2);
        var dogY = cy - (mFrameSize / 2) - 10;
        if (dogBitmap != null) {
            dc.setClip(dogX, dogY, mFrameSize, mFrameSize);
            dc.drawBitmap(dogX - (frameToDraw * mFrameSize), dogY, dogBitmap as WatchUi.BitmapResource);
            dc.clearClip();
        }
    }

    // Draws up to 6 of the 9 configurable fields from mFieldRender: two
    // columns hugging the watch's round edge, growing inward; up to three
    // rows stacked above the time block, filling bottom-left/right,
    // middle-left/right, top-left/right in that order. Nothing clips against
    // the dog sprite, so a wide value can overlap it.
    private function drawFields(dc as Dc, cx as Number, cy as Number, height as Number, pad as Number, subtextColor as Number) as Void {
        var textHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_XTINY);
        var scaledIconHeight = ((mFieldDefs[0][:icon] as WatchUi.BitmapResource).getHeight() * FIELD_ICON_SCALE).toNumber();
        var stackedRowHeight = scaledIconHeight + FIELD_ICON_TEXT_GAP + textHeight;

        var bottomGap = 4; // breathing room from the time block below
        var rowPadding = 6; // between adjacent field rows
        var bottomRowY = timeBlockTopY(height, pad) - bottomGap - stackedRowHeight;
        var middleRowY = bottomRowY - rowPadding - stackedRowHeight;
        var topRowY = middleRowY - rowPadding - stackedRowHeight;

        // Index order: bottom-left, bottom-right, middle-left, middle-right,
        // top-left, top-right. alignToRightEdge false = grows rightward
        // from the edge; true = grows leftward.
        var positionCoords = [
            { :alignToRightEdge => false, :rowY => bottomRowY },
            { :alignToRightEdge => true, :rowY => bottomRowY },
            { :alignToRightEdge => false, :rowY => middleRowY },
            { :alignToRightEdge => true, :rowY => middleRowY },
            { :alignToRightEdge => false, :rowY => topRowY },
            { :alignToRightEdge => true, :rowY => topRowY },
        ];

        for (var i = 0; i < mFieldRender.size(); i += 1) {
            var field = mFieldRender[i];
            if (field != null) {
                var coords = positionCoords[field[:position]];
                drawField(dc, cx, cy, coords[:alignToRightEdge], coords[:rowY], field[:icon] as WatchUi.BitmapResource, field[:text], subtextColor);
            }
        }
    }

    // One field: icon above value, stacked tightly. Icon and value each sit
    // as close to the round edge as their own rows allow, so they follow the
    // curve rather than sharing one anchor.
    private function drawField(dc as Dc, cx as Number, cy as Number, alignToRightEdge as Boolean, rowY as Number, icon as WatchUi.BitmapResource, valueText as String, subtextColor as Number) as Void {
        var font = Graphics.FONT_SYSTEM_XTINY;
        var textWidth = dc.getTextWidthInPixels(valueText, font);
        var textHeight = Graphics.getFontHeight(font);
        var scaledIconWidth = (icon.getWidth() * FIELD_ICON_SCALE).toNumber();
        var scaledIconHeight = (icon.getHeight() * FIELD_ICON_SCALE).toNumber();

        var iconY = rowY;
        var textY = rowY + scaledIconHeight + FIELD_ICON_TEXT_GAP;
        var iconHalfWidth = rowHalfWidth(iconY, scaledIconHeight, cx, cy) - FIELD_EDGE_MARGIN;
        var textHalfWidth = rowHalfWidth(textY, textHeight, cx, cy) - FIELD_EDGE_MARGIN;

        var iconX = cx - iconHalfWidth;
        var textX = cx - textHalfWidth;
        if (alignToRightEdge) {
            iconX = cx + iconHalfWidth - scaledIconWidth;
            textX = cx + textHalfWidth - textWidth;
        }

        dc.drawScaledBitmap(iconX, iconY, scaledIconWidth, scaledIconHeight, icon);
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

    private function currentStressLevel() as Number or Null {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getStressHistory)) {
            return null;
        }
        var iterator = SensorHistory.getStressHistory({});
        var sample = iterator.next();
        if (sample != null && sample.data != null) {
            return sample.data.toNumber();
        }
        return null;
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
    private function drawTimeDate(dc as Dc, cx as Number, height as Number, pad as Number, timeColor as Number, dateColor as Number) as Void {
        var dateHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_XTINY);
        var dateY = height - pad - dateHeight;
        var timeY = timeBlockTopY(height, pad);

        var clockTime = System.getClockTime();
        var hours = clockTime.hour;
        if (!mUseMilitaryFormat) {
            if (hours == 0) {
                hours = 12;
            } else if (hours > 12) {
                hours = hours - 12;
            }
        }
        var timeString = Lang.format("$1$:$2$", [hours, clockTime.min.format("%02d")]);
        dc.setColor(timeColor, Graphics.COLOR_TRANSPARENT);
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
        mFieldRender = null;
        mCachedDateString = null;
        invalidateFieldCache();
    }

    function onExitSleep() as Void {
        mIsAsleep = false;
        invalidateFieldCache();
        enterIdle();
    }

    function onEnterSleep() as Void {
        mIsAsleep = true;
        if (mAnimTimer != null) {
            mAnimTimer.stop();
        }
        resetToRestPose();
    }

}
