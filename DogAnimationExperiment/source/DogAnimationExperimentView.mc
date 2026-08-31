import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

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

        // Dog sprite — current animation frame, centered horizontally.
        // Clip to one frame's window and blit the whole sheet shifted left,
        // rather than relying on drawBitmap2's :bitmapX/:bitmapWidth crop.
        var dogBitmap = mStandingBitmap;
        var frameToDraw = FRAME_ORDER[mOrderIndex];
        if (mState != STATE_IDLE) {
            var clip = mTricks[mState][mClipIndex];
            dogBitmap = clip[:bitmap];
            frameToDraw = (clip[:startFrame] as Number) + mClipFrame;
        }

        if (dogBitmap != null) {
            var dogX = cx - (FRAME_SIZE / 2);
            var dogY = cy / 2 + pad;
            dc.setClip(dogX, dogY, FRAME_SIZE, FRAME_SIZE);
            dc.drawBitmap(dogX - (frameToDraw * FRAME_SIZE), dogY, dogBitmap as WatchUi.BitmapResource);
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
