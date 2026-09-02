import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function testBatteryIconIndexAtBoundaries(logger as Test.Logger) as Boolean {
    // 0=full, 1=threeQuarters, 2=half, 3=quarter, 4=empty. Checks the exact
    // threshold values (75/50/25/10) land on the lower band, not the upper
    // one, plus the extremes (100 and 0).
    var cases = [
        [100, 0], [76, 0],
        [75, 1], [51, 1],
        [50, 2], [26, 2],
        [25, 3], [11, 3],
        [10, 4], [0, 4],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var percent = cases[i][0];
        var expected = cases[i][1];
        var got = pickBatteryIconIndex(percent);
        if (got != expected) {
            logger.debug("percent=" + percent + " expected=" + expected + " got=" + got);
            ok = false;
        }
    }
    return ok;
}

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
    // Rules out a selection-bias bug (e.g. Math.rand() % trickCount always
    // landing on the same branch) hiding a trick behind the others every
    // time. trickCount here must match mTricks.size() in the view — update
    // if a trick is added or removed.
    var trickCount = 3;
    var seen = {};
    for (var i = 0; i < 90; i += 1) {
        seen[pickTrickIndex(Math.rand(), trickCount)] = true;
    }
    logger.debug("distinct outcomes seen=" + seen.size() + " expected=" + trickCount);
    return seen.size() == trickCount;
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
function testAllDrawablesLoad(logger as Test.Logger) as Boolean {
    // If any of these fail to load, onUpdate silently skips drawing the dog
    // entirely while in the matching state (dogBitmap stays null) — the
    // trick still fires but renders as a blank gap instead of the animation.
    // Checked together so adding a new sheet later means adding one line
    // here, not a new one-off test.
    var ok = true;
    ok = checkDrawableLoads(logger, "CorgiStanding", Rez.Drawables.CorgiStanding) && ok;
    ok = checkDrawableLoads(logger, "CorgiLicking", Rez.Drawables.CorgiLicking) && ok;
    ok = checkDrawableLoads(logger, "CorgiSitToStand", Rez.Drawables.CorgiSitToStand) && ok;
    ok = checkDrawableLoads(logger, "CorgiStandToSit", Rez.Drawables.CorgiStandToSit) && ok;
    ok = checkDrawableLoads(logger, "CorgiTailSpin", Rez.Drawables.CorgiTailSpin) && ok;
    ok = checkDrawableLoads(logger, "IconShoePrints", Rez.Drawables.IconShoePrints) && ok;
    ok = checkDrawableLoads(logger, "IconBatteryFull", Rez.Drawables.IconBatteryFull) && ok;
    ok = checkDrawableLoads(logger, "IconBatteryThreeQuarters", Rez.Drawables.IconBatteryThreeQuarters) && ok;
    ok = checkDrawableLoads(logger, "IconBatteryHalf", Rez.Drawables.IconBatteryHalf) && ok;
    ok = checkDrawableLoads(logger, "IconBatteryQuarter", Rez.Drawables.IconBatteryQuarter) && ok;
    ok = checkDrawableLoads(logger, "IconBatteryEmpty", Rez.Drawables.IconBatteryEmpty) && ok;
    return ok;
}

function checkDrawableLoads(logger as Test.Logger, name as String, id as ResourceId) as Boolean {
    var bitmap = WatchUi.loadResource(id);
    var loaded = bitmap != null;
    logger.debug(name + " loaded=" + loaded);
    return loaded;
}

(:test)
function testClipProgressWalksMultiClipTrick(logger as Test.Logger) as Boolean {
    // Walks the sit-down -> seated-pause -> stand-up trick's clip sequence
    // via the pure step function and asserts clip index + frame at each
    // tick. This is the exact class of off-by-one state-machine bug that
    // broke Phase 2 once, now generalized to any multi-clip trick rather
    // than hardcoded to this one.
    var clips = [
        { :frameCount => 5 }, // sit down
        { :frameCount => 1 }, // hold seated
        { :frameCount => 5 }, // stand back up
    ];

    var clipIndex = 0;
    var clipFrame = 0;
    var ok = true;
    var step;

    // Clip 0 (sit down): frames 0->1->2->3->4 across 5 ticks.
    for (var i = 0; i < 4; i += 1) {
        step = nextClipProgress(clipIndex, clipFrame, clips);
        clipIndex = step[0];
        clipFrame = step[1];
        if (clipIndex != 0 || clipFrame != i + 1) {
            logger.debug("sit-down step " + i + " got clip=" + clipIndex + " frame=" + clipFrame);
            ok = false;
        }
    }

    // 5th tick on clip 0 completes it -> advances to clip 1 (seated pause), frame reset to 0.
    step = nextClipProgress(clipIndex, clipFrame, clips);
    clipIndex = step[0];
    clipFrame = step[1];
    if (clipIndex != 1 || clipFrame != 0) {
        logger.debug("seated-pause entry got clip=" + clipIndex + " frame=" + clipFrame);
        ok = false;
    }

    // Pause tick (1-frame clip) completes immediately -> advances to clip 2 (stand up).
    step = nextClipProgress(clipIndex, clipFrame, clips);
    clipIndex = step[0];
    clipFrame = step[1];
    if (clipIndex != 2 || clipFrame != 0) {
        logger.debug("stand-up entry got clip=" + clipIndex + " frame=" + clipFrame);
        ok = false;
    }

    // Clip 2 (stand up): frames 0->1->2->3->4 across 5 ticks.
    for (var j = 0; j < 4; j += 1) {
        step = nextClipProgress(clipIndex, clipFrame, clips);
        clipIndex = step[0];
        clipFrame = step[1];
        if (clipIndex != 2 || clipFrame != j + 1) {
            logger.debug("stand-up step " + j + " got clip=" + clipIndex + " frame=" + clipFrame);
            ok = false;
        }
    }

    // Final tick signals trick completion: clipIndex advances past the last clip.
    step = nextClipProgress(clipIndex, clipFrame, clips);
    if (step[0] < clips.size()) {
        logger.debug("expected completion, got clip=" + step[0]);
        ok = false;
    }

    return ok;
}
