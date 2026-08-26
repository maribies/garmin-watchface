import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function testFrameOrderAdvances(logger as Test.Logger) as Boolean {
    // FRAME_ORDER = [0,1,0,2]; starting at index 0 (rest), 5 ticks should
    // walk one full cycle and one step into the next: 1,0,2,0,1.
    var idx = 0;
    idx = advanceOrderIndex(idx);
    var frame1 = FRAME_ORDER[idx];
    idx = advanceOrderIndex(idx);
    var frame2 = FRAME_ORDER[idx];
    idx = advanceOrderIndex(idx);
    var frame3 = FRAME_ORDER[idx];
    idx = advanceOrderIndex(idx);
    var frame4 = FRAME_ORDER[idx];
    idx = advanceOrderIndex(idx);
    var frame5 = FRAME_ORDER[idx];

    logger.debug(frame1 + "," + frame2 + "," + frame3 + "," + frame4 + "," + frame5);

    return frame1 == 1 && frame2 == 0 && frame3 == 2 && frame4 == 0 && frame5 == 1;
}

(:test)
function testRestFrameIsFirstInOrder(logger as Test.Logger) as Boolean {
    // onEnterSleep resets to FRAME_ORDER[0]; this must stay the calm/rest
    // pose (frame 0) so sleep mode never freezes on a bob or blink frame.
    logger.debug("FRAME_ORDER[0]=" + FRAME_ORDER[0]);
    return FRAME_ORDER[0] == 0;
}

(:test)
function testTrickSelectionCanPickAllOutcomes(logger as Test.Logger) as Boolean {
    // Rules out a selection-bias bug (e.g. Math.rand() % 3 always landing on
    // the same branch) hiding a trick behind the others every time.
    var sawLick = false;
    var sawSitDown = false;
    var sawTailSpin = false;
    for (var i = 0; i < 90; i += 1) {
        var picked = pickTrickState(Math.rand());
        if (picked == STATE_LICK) {
            sawLick = true;
        } else if (picked == STATE_SIT_DOWN) {
            sawSitDown = true;
        } else if (picked == STATE_TAIL_SPIN) {
            sawTailSpin = true;
        }
    }
    logger.debug("sawLick=" + sawLick + " sawSitDown=" + sawSitDown + " sawTailSpin=" + sawTailSpin);
    return sawLick && sawSitDown && sawTailSpin;
}

(:test)
function testTicksFromRandomStaysInBounds(logger as Test.Logger) as Boolean {
    var ok = true;
    for (var i = 0; i < 50; i += 1) {
        var ticks = ticksFromRandom(Math.rand());
        if (ticks < MIN_TRICK_DELAY_TICKS || ticks > MAX_TRICK_DELAY_TICKS) {
            logger.debug("out of bounds: " + ticks);
            ok = false;
        }
    }
    return ok;
}

(:test)
function testLickingBitmapLoads(logger as Test.Logger) as Boolean {
    // If CorgiLicking failed to load, onUpdate silently skips drawing the
    // dog entirely while in STATE_LICK (dogBitmap stays null) — the lick
    // trick would fire but render as a blank gap instead of the animation.
    var bitmap = WatchUi.loadResource(Rez.Drawables.CorgiLicking);
    logger.debug("CorgiLicking loaded=" + (bitmap != null));
    return bitmap != null;
}

(:test)
function testTailSpinBitmapLoads(logger as Test.Logger) as Boolean {
    // Same resource-loading sanity check as testLickingBitmapLoads, for the
    // Phase 4 tail-spin sheet.
    var bitmap = WatchUi.loadResource(Rez.Drawables.CorgiTailSpin);
    logger.debug("CorgiTailSpin loaded=" + (bitmap != null));
    return bitmap != null;
}

(:test)
function testTrickSequenceWalksSitPauseStand(logger as Test.Logger) as Boolean {
    // Walks the full sit-down -> seated-pause -> stand-up sequence via the
    // pure step function and asserts state+frame at each tick. This is the
    // exact class of off-by-one state-machine bug that broke Phase 2 once.
    var state = STATE_SIT_DOWN;
    var frame = 0;
    var ok = true;
    var step;

    // STAND_TO_SIT_FRAME_COUNT = 5: frames 0->1->2->3->4 while still SIT_DOWN.
    for (var i = 0; i < STAND_TO_SIT_FRAME_COUNT - 1; i += 1) {
        step = nextTrickStep(state, frame);
        state = step[0];
        frame = step[1];
        if (state != STATE_SIT_DOWN || frame != i + 1) {
            logger.debug("sit-down step " + i + " got state=" + state + " frame=" + frame);
            ok = false;
        }
    }

    // 5th tick: last sit-down frame reached -> switches to SEATED_PAUSE,
    // holding on the fully-seated frame (index STAND_TO_SIT_FRAME_COUNT-1).
    step = nextTrickStep(state, frame);
    state = step[0];
    frame = step[1];
    if (state != STATE_SEATED_PAUSE || frame != STAND_TO_SIT_FRAME_COUNT - 1) {
        logger.debug("seated-pause entry got state=" + state + " frame=" + frame);
        ok = false;
    }

    // Pause tick -> STAND_UP, frame reset to 0.
    step = nextTrickStep(state, frame);
    state = step[0];
    frame = step[1];
    if (state != STATE_STAND_UP || frame != 0) {
        logger.debug("stand-up entry got state=" + state + " frame=" + frame);
        ok = false;
    }

    // SIT_TO_STAND_FRAME_COUNT = 5: frames 0->1->2->3->4 while still STAND_UP.
    for (var j = 0; j < SIT_TO_STAND_FRAME_COUNT - 1; j += 1) {
        step = nextTrickStep(state, frame);
        state = step[0];
        frame = step[1];
        if (state != STATE_STAND_UP || frame != j + 1) {
            logger.debug("stand-up step " + j + " got state=" + state + " frame=" + frame);
            ok = false;
        }
    }

    // Final stand-up tick signals completion back to IDLE.
    step = nextTrickStep(state, frame);
    if (step[0] != STATE_IDLE) {
        logger.debug("completion got state=" + step[0]);
        ok = false;
    }

    return ok;
}
