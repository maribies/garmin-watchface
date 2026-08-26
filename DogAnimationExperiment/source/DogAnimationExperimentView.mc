import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// All corgi sprite sheets use 120x120 frames.
const FRAME_SIZE = 120;
const ANIM_TICK_MS = 100;

const STATE_SIT = 0;
const STATE_SIT_TO_STAND = 1;
const STATE_STANDING = 2;
const STATE_STAND_TO_SIT = 3;

const SIT_TO_STAND_FRAMES = 5;
const STANDING_FRAMES = 3;
const STAND_TO_SIT_FRAMES = 5;

// Hold durations, in animation ticks (ANIM_TICK_MS each).
const SIT_HOLD_TICKS = 40; // ~4s sitting before standing back up
const STANDING_HOLD_TICKS = 30; // ~3s standing before sitting back down

class DogAnimationExperimentView extends WatchUi.WatchFace {

    private var mSitToStandBitmap = null;
    private var mStandingBitmap = null;
    private var mStandToSitBitmap = null;

    private var mAnimTimer = null;
    private var mAnimState = STATE_SIT;
    private var mFrameIndex = 0;
    private var mHoldTicksRemaining = SIT_HOLD_TICKS;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        mSitToStandBitmap = WatchUi.loadResource(Rez.Drawables.CorgiSitToStand);
        mStandingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStanding);
        mStandToSitBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStandToSit);
    }

    function onShow() as Void {
    }

    // Advances the animation state machine by one tick:
    // SIT (hold) -> SIT_TO_STAND (play) -> STANDING (hold/loop) -> STAND_TO_SIT (play) -> SIT ...
    function onAnimTimer() as Void {
        if (mAnimState == STATE_SIT) {
            mHoldTicksRemaining -= 1;
            if (mHoldTicksRemaining <= 0) {
                mAnimState = STATE_SIT_TO_STAND;
                mFrameIndex = 0;
            }
        } else if (mAnimState == STATE_SIT_TO_STAND) {
            mFrameIndex += 1;
            if (mFrameIndex >= SIT_TO_STAND_FRAMES) {
                mAnimState = STATE_STANDING;
                mFrameIndex = 0;
                mHoldTicksRemaining = STANDING_HOLD_TICKS;
            }
        } else if (mAnimState == STATE_STANDING) {
            mFrameIndex = (mFrameIndex + 1) % STANDING_FRAMES;
            mHoldTicksRemaining -= 1;
            if (mHoldTicksRemaining <= 0) {
                mAnimState = STATE_STAND_TO_SIT;
                mFrameIndex = 0;
            }
        } else if (mAnimState == STATE_STAND_TO_SIT) {
            mFrameIndex += 1;
            if (mFrameIndex >= STAND_TO_SIT_FRAMES) {
                mAnimState = STATE_SIT;
                mFrameIndex = 0;
                mHoldTicksRemaining = SIT_HOLD_TICKS;
            }
        }

        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var cx = width / 2;
        var height = dc.getHeight();
        var cy = height / 2;
        var pad = 10;

        // Background
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();

        // Time
        var clockTime = System.getClockTime();
        var hours = clockTime.hour;
        var deviceSettings = System.getDeviceSettings();
        if (!deviceSettings.is24Hour) {
            if (hours == 0) {
                hours = 12;
            } else if (hours > 12) {
                hours = hours - 12;
            }
        }
        var timeString = Lang.format("$1$:$2$", [hours, clockTime.min.format("%02d")]);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, pad, Graphics.FONT_SYSTEM_LARGE, timeString, Graphics.TEXT_JUSTIFY_CENTER);

        // Date
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateString = Lang.format("$1$ $2$ $3$", [today.day_of_week, today.month, today.day]);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        var timeHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_LARGE);
        dc.drawText(cx, timeHeight + pad, Graphics.FONT_SYSTEM_XTINY, dateString, Graphics.TEXT_JUSTIFY_CENTER);

        // Dog sprite — current animation frame, centered horizontally
        var dogBitmap = null;
        if (mAnimState == STATE_SIT) {
            dogBitmap = mSitToStandBitmap;
        } else if (mAnimState == STATE_SIT_TO_STAND) {
            dogBitmap = mSitToStandBitmap;
        } else if (mAnimState == STATE_STANDING) {
            dogBitmap = mStandingBitmap;
        } else {
            dogBitmap = mStandToSitBitmap;
        }

        if (dogBitmap != null) {
            var dogX = cx - (FRAME_SIZE / 2);
            var dogY = cy / 2 + pad;
            dc.drawBitmap2(dogX, dogY, dogBitmap as WatchUi.BitmapResource, {
                :bitmapX => mFrameIndex * FRAME_SIZE,
                :bitmapY => 0,
                :bitmapWidth => FRAME_SIZE,
                :bitmapHeight => FRAME_SIZE
            });
        }

        // Steps
        var steps = 0;
        var activityInfo = ActivityMonitor.getInfo();
        if (activityInfo != null && activityInfo.steps != null) {
            steps = activityInfo.steps as Number;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - cx / 2, cy + cy / 2, Graphics.FONT_SYSTEM_XTINY, steps.toString() + " steps", Graphics.TEXT_JUSTIFY_LEFT);

        // Battery
        var stats = System.getSystemStats();
        var battery = stats.battery.toNumber();
        dc.drawText(cx + cx / 2, cy + cy / 2, Graphics.FONT_SYSTEM_XTINY, battery.toString() + "%", Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function onHide() as Void {
        mSitToStandBitmap = null;
        mStandingBitmap = null;
        mStandToSitBitmap = null;
    }

    function onExitSleep() as Void {
        if (mAnimTimer == null) {
            mAnimTimer = new Timer.Timer();
        }
        mAnimTimer.start(method(:onAnimTimer), ANIM_TICK_MS, true);
    }

    function onEnterSleep() as Void {
        if (mAnimTimer != null) {
            mAnimTimer.stop();
        }
        // Show only the static sitting pose while asleep.
        mAnimState = STATE_SIT;
        mFrameIndex = 0;
        mHoldTicksRemaining = SIT_HOLD_TICKS;
    }

}
