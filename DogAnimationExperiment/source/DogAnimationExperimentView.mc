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
const ANIM_TICK_MS = 400;
// Standing idle play order: rest, bob-down, rest, blink-closed (see planning/sprite-recipe.md)
const FRAME_ORDER = [0, 1, 0, 2];

// Pulled out of the view so it's testable without touching private view state.
function advanceOrderIndex(current as Number) as Number {
    return (current + 1) % FRAME_ORDER.size();
}

class DogAnimationExperimentView extends WatchUi.WatchFace {

    private var mStandingBitmap = null;

    private var mAnimTimer = null;
    private var mOrderIndex = 0;
    private var mFrameIndex = FRAME_ORDER[0];

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        mStandingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStanding);
    }

    function onShow() as Void {
    }

    function onAnimTimer() as Void {
        mOrderIndex = advanceOrderIndex(mOrderIndex);
        mFrameIndex = FRAME_ORDER[mOrderIndex];
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

        // Dog sprite — current standing-sheet frame, centered horizontally.
        // Clip to one frame's window and blit the whole sheet shifted left,
        // rather than relying on drawBitmap2's :bitmapX/:bitmapWidth crop.
        if (mStandingBitmap != null) {
            var dogX = cx - (FRAME_SIZE / 2);
            var dogY = cy / 2 + pad;
            dc.setClip(dogX, dogY, FRAME_SIZE, FRAME_SIZE);
            dc.drawBitmap(dogX - (mFrameIndex * FRAME_SIZE), dogY, mStandingBitmap as WatchUi.BitmapResource);
            dc.clearClip();
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
        mStandingBitmap = null;
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
        mOrderIndex = 0;
        mFrameIndex = FRAME_ORDER[0];
    }

}
