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

const LICK_FRAME_COUNT = 11;
const LICK_TICK_MS = 150;

const SIT_TO_STAND_FRAME_COUNT = 5;
const STAND_TO_SIT_FRAME_COUNT = 5;
const STAND_TICK_MS = 120;
const SEATED_PAUSE_MS = 1000;

const TAIL_SPIN_FRAME_COUNT = 9;
const TAIL_SPIN_TICK_MS = 130;

// Random trick trigger window, counted in idle ticks (8-20s at IDLE_TICK_MS).
const MIN_TRICK_DELAY_TICKS = 20;
const MAX_TRICK_DELAY_TICKS = 50;

const STATE_IDLE = 0;
const STATE_LICK = 1;
const STATE_SIT_DOWN = 2;
const STATE_SEATED_PAUSE = 3;
const STATE_STAND_UP = 4;
const STATE_TAIL_SPIN = 5;

// Pulled out of the view so it's testable without touching private view state.
function advanceOrderIndex(current as Number) as Number {
    return (current + 1) % FRAME_ORDER.size();
}

// Maps a raw random value to a trick delay within [MIN_TRICK_DELAY_TICKS, MAX_TRICK_DELAY_TICKS].
function ticksFromRandom(raw as Number) as Number {
    var span = MAX_TRICK_DELAY_TICKS - MIN_TRICK_DELAY_TICKS + 1;
    return MIN_TRICK_DELAY_TICKS + (raw % span);
}

// Maps a raw random value to which trick plays next.
function pickTrickState(raw as Number) as Number {
    var pick = raw % 3;
    if (pick == 0) {
        return STATE_LICK;
    } else if (pick == 1) {
        return STATE_SIT_DOWN;
    }
    return STATE_TAIL_SPIN;
}

// One tick of the sit-down -> seated-pause -> stand-up sequence, as
// [nextState, nextFrameIndex]. Only valid for those three states — IDLE/LICK
// ticking and the full reset on trick completion are handled by the view.
// Completion is signaled by returning STATE_IDLE; the caller is responsible
// for calling enterIdle() (timer reconfig + re-rolled trick delay) rather
// than applying the returned frame index directly in that case.
function nextTrickStep(state as Number, frameIndex as Number) as Array<Number> {
    if (state == STATE_SIT_DOWN) {
        var next = frameIndex + 1;
        if (next >= STAND_TO_SIT_FRAME_COUNT) {
            return [STATE_SEATED_PAUSE, STAND_TO_SIT_FRAME_COUNT - 1]; // hold on the fully-seated frame
        }
        return [STATE_SIT_DOWN, next];
    } else if (state == STATE_SEATED_PAUSE) {
        return [STATE_STAND_UP, 0];
    } else if (state == STATE_STAND_UP) {
        var next = frameIndex + 1;
        if (next >= SIT_TO_STAND_FRAME_COUNT) {
            return [STATE_IDLE, 0];
        }
        return [STATE_STAND_UP, next];
    }
    return [state, frameIndex];
}

class DogAnimationExperimentView extends WatchUi.WatchFace {

    private var mStandingBitmap = null;
    private var mLickingBitmap = null;
    private var mSitToStandBitmap = null;
    private var mStandToSitBitmap = null;
    private var mTailSpinBitmap = null;

    private var mAnimTimer = null;
    private var mState = STATE_IDLE;
    private var mOrderIndex = 0;
    private var mFrameIndex = FRAME_ORDER[0];
    private var mTicksUntilTrick = MIN_TRICK_DELAY_TICKS;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        mStandingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStanding);
        mLickingBitmap = WatchUi.loadResource(Rez.Drawables.CorgiLicking);
        mSitToStandBitmap = WatchUi.loadResource(Rez.Drawables.CorgiSitToStand);
        mStandToSitBitmap = WatchUi.loadResource(Rez.Drawables.CorgiStandToSit);
        mTailSpinBitmap = WatchUi.loadResource(Rez.Drawables.CorgiTailSpin);
    }

    function onShow() as Void {
    }

    // Idle (standing, blinking) -> random trick (lick, sit-down/pause/stand-up, or tail spin) -> idle ...
    function onAnimTimer() as Void {
        if (mState == STATE_IDLE) {
            mOrderIndex = advanceOrderIndex(mOrderIndex);
            mFrameIndex = FRAME_ORDER[mOrderIndex];
            mTicksUntilTrick -= 1;
            if (mTicksUntilTrick <= 0) {
                startRandomTrick();
            }
        } else if (mState == STATE_LICK) {
            mFrameIndex += 1;
            if (mFrameIndex >= LICK_FRAME_COUNT) {
                enterIdle();
            }
        } else if (mState == STATE_TAIL_SPIN) {
            mFrameIndex += 1;
            if (mFrameIndex >= TAIL_SPIN_FRAME_COUNT) {
                enterIdle();
            }
        } else {
            // STATE_SIT_DOWN, STATE_SEATED_PAUSE, STATE_STAND_UP
            var prevState = mState;
            var step = nextTrickStep(mState, mFrameIndex);
            if (prevState == STATE_STAND_UP && step[0] == STATE_IDLE) {
                enterIdle();
            } else {
                mState = step[0];
                mFrameIndex = step[1];
                if (mState != prevState) {
                    configureTimerForState();
                }
            }
        }

        WatchUi.requestUpdate();
    }

    function startRandomTrick() as Void {
        mState = pickTrickState(Math.rand());
        mFrameIndex = 0;
        configureTimerForState();
    }

    function enterIdle() as Void {
        mState = STATE_IDLE;
        mOrderIndex = 0;
        mFrameIndex = FRAME_ORDER[0];
        mTicksUntilTrick = ticksFromRandom(Math.rand());
        configureTimerForState();
    }

    // (Re)starts mAnimTimer at the tick rate/repeat mode the current state needs.
    function configureTimerForState() as Void {
        if (mAnimTimer == null) {
            mAnimTimer = new Timer.Timer();
        }
        if (mState == STATE_IDLE) {
            mAnimTimer.start(method(:onAnimTimer), IDLE_TICK_MS, true);
        } else if (mState == STATE_LICK) {
            mAnimTimer.start(method(:onAnimTimer), LICK_TICK_MS, true);
        } else if (mState == STATE_SIT_DOWN || mState == STATE_STAND_UP) {
            mAnimTimer.start(method(:onAnimTimer), STAND_TICK_MS, true);
        } else if (mState == STATE_SEATED_PAUSE) {
            mAnimTimer.start(method(:onAnimTimer), SEATED_PAUSE_MS, false);
        } else if (mState == STATE_TAIL_SPIN) {
            mAnimTimer.start(method(:onAnimTimer), TAIL_SPIN_TICK_MS, true);
        }
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
        if (mState == STATE_LICK) {
            dogBitmap = mLickingBitmap;
        } else if (mState == STATE_SIT_DOWN || mState == STATE_SEATED_PAUSE) {
            dogBitmap = mStandToSitBitmap;
        } else if (mState == STATE_STAND_UP) {
            dogBitmap = mSitToStandBitmap;
        } else if (mState == STATE_TAIL_SPIN) {
            dogBitmap = mTailSpinBitmap;
        }

        if (dogBitmap != null) {
            var dogX = cx - (FRAME_SIZE / 2);
            var dogY = cy / 2 + pad;
            dc.setClip(dogX, dogY, FRAME_SIZE, FRAME_SIZE);
            dc.drawBitmap(dogX - (mFrameIndex * FRAME_SIZE), dogY, dogBitmap as WatchUi.BitmapResource);
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
        mLickingBitmap = null;
        mSitToStandBitmap = null;
        mStandToSitBitmap = null;
        mTailSpinBitmap = null;
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
        mFrameIndex = FRAME_ORDER[0];
    }

}
