import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Sprite sheet: 8 frames, each 42px wide x 46px tall
const SPRITE_FRAME_WIDTH = 42;

class DogAnimationExperimentView extends WatchUi.WatchFace {

    private var mDogBitmap = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        mDogBitmap = WatchUi.loadResource(Rez.Drawables.DogSprite);
    }

    function onShow() as Void {
    }

    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var cx = width / 2;
        var height = dc.getHeight();
        var cy = height / 2;
        var pad = 10;

        // Background
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, pad, Graphics.FONT_SYSTEM_LARGE, timeString, Graphics.TEXT_JUSTIFY_CENTER);

        // Date
        var today = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateString = Lang.format("$1$ $2$ $3$", [today.day_of_week, today.month, today.day]);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var timeHeight = Graphics.getFontHeight(Graphics.FONT_SYSTEM_LARGE);
        dc.drawText(cx, timeHeight + pad, Graphics.FONT_SYSTEM_XTINY, dateString, Graphics.TEXT_JUSTIFY_CENTER);

        // Dog sprite — first frame of sheet, centered horizontally
        if (mDogBitmap != null) {
            var frameH = (mDogBitmap as WatchUi.BitmapResource).getHeight();
            var dogX = cx - (SPRITE_FRAME_WIDTH / 2);
            var dogY = cy / 2 + pad;
            dc.drawBitmap2(dogX, dogY, mDogBitmap as WatchUi.BitmapResource, {
                :bitmapX => 0,
                :bitmapY => 0,
                :bitmapWidth => SPRITE_FRAME_WIDTH,
                :bitmapHeight => frameH
            });
        }

        // Steps
        var steps = 0;
        var activityInfo = ActivityMonitor.getInfo();
        if (activityInfo != null && activityInfo.steps != null) {
            steps = activityInfo.steps as Number;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - cx / 2, cy + cy / 2, Graphics.FONT_SYSTEM_XTINY, steps.toString() + " steps", Graphics.TEXT_JUSTIFY_LEFT);

        // Battery
        var stats = System.getSystemStats();
        var battery = stats.battery.toNumber();
        dc.drawText(cx + cx / 2, cy + cy / 2, Graphics.FONT_SYSTEM_XTINY, battery.toString() + "%", Graphics.TEXT_JUSTIFY_RIGHT);
    }

    function onHide() as Void {
        mDogBitmap = null;
    }

    function onExitSleep() as Void {
    }

    function onEnterSleep() as Void {
    }

}
