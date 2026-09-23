import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;
import Toybox.WatchUi;
import Toybox.Weather;

(:test)
function testBackgroundColorsAreArgb2222Safe(logger as Test.Logger) as Boolean {
    // Must match the listEntry values in resources/settings/settings.xml
    // exactly — this test is only meaningful if it's checking the actual
    // shipped palette, not a stand-in.
    var colors = {
        "LightRed" => 0xFFAAAA,
        "LightBlue" => 0xAAAAFF,
        "LightYellow" => 0xFFFFAA,
        "LightGreen" => 0xAAFFAA,
        "LightPurple" => 0xFFAAFF,
        "LightOrange" => 0xFFAA55,
    };
    var ok = true;
    var names = colors.keys();
    for (var i = 0; i < names.size(); i += 1) {
        var name = names[i];
        var color = colors[name];
        var safe = isArgb2222Safe(color);
        if (!safe) {
            logger.debug(name + "=0x" + color.format("%X") + " is not ARGB2222-safe");
            ok = false;
        }
    }
    return ok;
}

(:test)
function testAssignFieldPositionsFillsBottomUpLeftToRight(logger as Test.Logger) as Boolean {
    // Fill order is bottom-left(0), bottom-right(1), middle-left(2),
    // middle-right(3), top-left(4), top-right(5) — positions are assigned
    // in fixed evaluation order (the 9 fields, steps first), not by which
    // specific fields are on. At most 6 of the 9 candidates get a position.
    var cases = [
        // [enabled, expectedPositions]
        [[false, false, false, false, false, false, false, false, false],
         [null, null, null, null, null, null, null, null, null]],
        [[true, false, false, false, false, false, false, false, false],
         [0, null, null, null, null, null, null, null, null]],
        [[false, true, false, false, false, false, false, false, false],
         [null, 0, null, null, null, null, null, null, null]],
        [[true, true, true, true, true, true, false, false, false],
         [0, 1, 2, 3, 4, 5, null, null, null]],
        // 7th enabled field (index 6) exceeds the 6-slot cap -> null.
        [[true, true, true, true, true, true, true, false, false],
         [0, 1, 2, 3, 4, 5, null, null, null]],
        // Only the last two candidates enabled -> still fill from position 0.
        [[false, false, false, false, false, false, false, true, true],
         [null, null, null, null, null, null, null, 0, 1]],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var enabled = cases[i][0];
        var expected = cases[i][1];
        var got = assignFieldPositions(enabled);
        for (var j = 0; j < expected.size(); j += 1) {
            if (got[j] != expected[j]) {
                logger.debug("case " + i + " index " + j + " expected=" + expected[j] + " got=" + got[j]);
                ok = false;
            }
        }
    }
    return ok;
}

(:test)
function testFormatDistanceConvertsAndFallsBack(logger as Test.Logger) as Boolean {
    var ok = true;
    // Metric: 520000cm -> 5.2km.
    if (!formatDistance(520000, false).equals("5.2")) {
        logger.debug("metric case got " + formatDistance(520000, false));
        ok = false;
    }
    // Statute: 160934cm ~= 1 mile.
    if (!formatDistance(160934, true).equals("1.0")) {
        logger.debug("statute case got " + formatDistance(160934, true));
        ok = false;
    }
    // Unavailable.
    if (!formatDistance(null, false).equals("--")) {
        logger.debug("null case got " + formatDistance(null, false));
        ok = false;
    }
    // Zero is a real, valid distance, not a fallback.
    if (!formatDistance(0, false).equals("0.0")) {
        logger.debug("zero case got " + formatDistance(0, false));
        ok = false;
    }
    return ok;
}

(:test)
function testChordHalfWidthAtMatchesCircleGeometry(logger as Test.Logger) as Boolean {
    // cx=cy=100 (radius 100): at center, half-width is the full radius; at
    // the very top/bottom edge, it's 0; a 60/80/100 case checks the actual
    // sqrt(r^2 - dy^2) math, not just the two trivial endpoints; symmetric
    // above and below center.
    var cx = 100;
    var cy = 100;
    var cases = [
        // [y, expectedHalfWidth]
        [100, 100],
        [0, 0],
        [200, 0],
        [160, 80], // dy=60 -> sqrt(100^2-60^2)=80
        [40, 80], // dy=60 above center, same as below
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var y = cases[i][0];
        var expected = cases[i][1];
        var got = chordHalfWidthAt(y, cx, cy);
        if (got != expected) {
            logger.debug("y=" + y + " expected=" + expected + " got=" + got);
            ok = false;
        }
    }
    return ok;
}

(:test)
function testDarkerTintStepsDownSafeLadder(logger as Test.Logger) as Boolean {
    // darkerTint must produce a color that's still ARGB2222-safe (each
    // channel stays in the {0x00,0x55,0xAA,0xFF} ladder) since it's used to
    // derive on-screen subtext color directly from the user's chosen background.
    var cases = [
        // [color, expected]
        [0xFFAAAA, 0xAA5555],
        [0xAAAAFF, 0x5555AA],
        [0xFFFFAA, 0xAAAA55],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var color = cases[i][0];
        var expected = cases[i][1];
        var got = darkerTint(color);
        if (got != expected) {
            logger.debug("color=0x" + color.format("%X") + " expected=0x" + expected.format("%X") + " got=0x" + got.format("%X"));
            ok = false;
        }
        if (!isArgb2222Safe(got)) {
            logger.debug("darkerTint(0x" + color.format("%X") + ") = 0x" + got.format("%X") + " is not ARGB2222-safe");
            ok = false;
        }
    }
    return ok;
}

(:test)
function testFormatFieldValueFallsBackWhenNull(logger as Test.Logger) as Boolean {
    var ok = true;
    if (!formatFieldValue(null, "%").equals("--")) {
        logger.debug("expected -- for null, got " + formatFieldValue(null, "%"));
        ok = false;
    }
    if (!formatFieldValue(56, "").equals("56")) {
        logger.debug("expected 56, got " + formatFieldValue(56, ""));
        ok = false;
    }
    if (!formatFieldValue(55, "%").equals("55%")) {
        logger.debug("expected 55%, got " + formatFieldValue(55, "%"));
        ok = false;
    }
    return ok;
}

(:test)
function testFormatStepsAbbreviatesAtOneHundredThousand(logger as Test.Logger) as Boolean {
    var cases = [
        // [steps, expected]
        [null, "--"],
        [0, "0"],
        [9999, "9999"],
        [99999, "99999"],
        [100000, "+100k"],
        [100999, "+100k"],
        [101000, "+101k"],
        [110000, "+110k"],
        [200000, "+200k"],
        [999999, "+999k"],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var steps = cases[i][0];
        var expected = cases[i][1];
        var got = formatSteps(steps);
        if (!got.equals(expected)) {
            logger.debug("steps=" + steps + " expected=" + expected + " got=" + got);
            ok = false;
        }
    }
    return ok;
}

(:test)
function testFormatTemperatureRangeConvertsAndFallsBack(logger as Test.Logger) as Boolean {
    var ok = true;
    // Metric: passes through, rounded.
    if (!formatTemperatureRange(20.0, 18.0, false).equals("20/18")) {
        logger.debug("metric case got " + formatTemperatureRange(20.0, 18.0, false));
        ok = false;
    }
    // Statute: converts C->F.
    if (!formatTemperatureRange(20.0, 18.0, true).equals("68/64")) {
        logger.debug("statute case got " + formatTemperatureRange(20.0, 18.0, true));
        ok = false;
    }
    // Either side missing falls back to "--" independently.
    if (!formatTemperatureRange(null, 18.0, false).equals("--/18")) {
        logger.debug("missing-high case got " + formatTemperatureRange(null, 18.0, false));
        ok = false;
    }
    if (!formatTemperatureRange(null, null, false).equals("--/--")) {
        logger.debug("both-missing case got " + formatTemperatureRange(null, null, false));
        ok = false;
    }
    return ok;
}

(:test)
function testWeatherIconKeyMapsConditionFamilies(logger as Test.Logger) as Boolean {
    var cases = [
        // [condition, expectedKey]
        [Weather.CONDITION_CLEAR, :sun],
        [Weather.CONDITION_PARTLY_CLEAR, :sun],
        [Weather.CONDITION_MOSTLY_CLEAR, :sun],
        [Weather.CONDITION_PARTLY_CLOUDY, :cloudSun],
        [Weather.CONDITION_MOSTLY_CLOUDY, :cloud],
        [Weather.CONDITION_CLOUDY, :cloud],
        [Weather.CONDITION_RAIN, :cloudRain],
        [Weather.CONDITION_LIGHT_RAIN, :cloudRain],
        [Weather.CONDITION_DRIZZLE, :cloudRain],
        [Weather.CONDITION_THUNDERSTORMS, :cloudBolt],
        [Weather.CONDITION_SCATTERED_THUNDERSTORMS, :cloudBolt],
        [Weather.CONDITION_SNOW, :snowflake],
        [Weather.CONDITION_LIGHT_SNOW, :snowflake],
        [Weather.CONDITION_WINTRY_MIX, :snowflake],
        [Weather.CONDITION_HAIL, :snowflake],
        [Weather.CONDITION_WINDY, :thermometer],
        [Weather.CONDITION_FOG, :thermometer],
        [null, :thermometer],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var condition = cases[i][0];
        var expected = cases[i][1];
        var got = weatherIconKey(condition);
        if (got != expected) {
            logger.debug("condition=" + condition + " expected=" + expected + " got=" + got);
            ok = false;
        }
    }
    return ok;
}

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
function testIsLowBatteryAtThreshold(logger as Test.Logger) as Boolean {
    // Threshold itself counts as low (<=), not just strictly below it.
    var cases = [
        [21, 20, false], [20, 20, true], [19, 20, true], [0, 20, true],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var percent = cases[i][0];
        var threshold = cases[i][1];
        var expected = cases[i][2];
        var got = isLowBattery(percent, threshold);
        if (got != expected) {
            logger.debug("percent=" + percent + " threshold=" + threshold + " expected=" + expected + " got=" + got);
            ok = false;
        }
    }
    return ok;
}

(:test)
function testIsMoveBarMaxAtThreshold(logger as Test.Logger) as Boolean {
    var cases = [
        [4, 5, false], [5, 5, true], [6, 5, true], [0, 5, false],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var level = cases[i][0];
        var maxLevel = cases[i][1];
        var expected = cases[i][2];
        var got = isMoveBarMax(level, maxLevel);
        if (got != expected) {
            logger.debug("level=" + level + " maxLevel=" + maxLevel + " expected=" + expected + " got=" + got);
            ok = false;
        }
    }
    return ok;
}

(:test)
function testIsHighStressAtThreshold(logger as Test.Logger) as Boolean {
    var cases = [
        [75, 76, false], [76, 76, true], [100, 76, true], [0, 76, false],
    ];
    var ok = true;
    for (var i = 0; i < cases.size(); i += 1) {
        var level = cases[i][0];
        var threshold = cases[i][1];
        var expected = cases[i][2];
        var got = isHighStress(level, threshold);
        if (got != expected) {
            logger.debug("level=" + level + " threshold=" + threshold + " expected=" + expected + " got=" + got);
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
    var view = new DogAnimationExperimentView();
    view.onShow();
    var trickCount = view.randomTrickPoolSize();
    view.onHide();

    var seen = {};
    for (var i = 0; i < 30 * trickCount; i += 1) {
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
    ok = checkDrawableLoads(logger, "CorgiSplootRear", Rez.Drawables.CorgiSplootRear) && ok;
    ok = checkDrawableLoads(logger, "CorgiSplootFront", Rez.Drawables.CorgiSplootFront) && ok;
    ok = checkDrawableLoads(logger, "CorgiTailSpin", Rez.Drawables.CorgiTailSpin) && ok;
    ok = checkDrawableLoads(logger, "CorgiFootTaps", Rez.Drawables.CorgiFootTaps) && ok;
    ok = checkDrawableLoads(logger, "AussieStanding", Rez.Drawables.AussieStanding) && ok;
    ok = checkDrawableLoads(logger, "AussieLicking", Rez.Drawables.AussieLicking) && ok;
    ok = checkDrawableLoads(logger, "AussieSplootRear", Rez.Drawables.AussieSplootRear) && ok;
    ok = checkDrawableLoads(logger, "AussieSplootFront", Rez.Drawables.AussieSplootFront) && ok;
    ok = checkDrawableLoads(logger, "AussieTailSpin", Rez.Drawables.AussieTailSpin) && ok;
    ok = checkDrawableLoads(logger, "AussieFootTaps", Rez.Drawables.AussieFootTaps) && ok;
    ok = checkDrawableLoads(logger, "IconShoePrints", Rez.Drawables.IconShoePrints) && ok;
    ok = checkDrawableLoads(logger, "IconHeart", Rez.Drawables.IconHeart) && ok;
    ok = checkDrawableLoads(logger, "IconSun", Rez.Drawables.IconSun) && ok;
    ok = checkDrawableLoads(logger, "IconCloudSun", Rez.Drawables.IconCloudSun) && ok;
    ok = checkDrawableLoads(logger, "IconCloud", Rez.Drawables.IconCloud) && ok;
    ok = checkDrawableLoads(logger, "IconCloudRain", Rez.Drawables.IconCloudRain) && ok;
    ok = checkDrawableLoads(logger, "IconCloudBolt", Rez.Drawables.IconCloudBolt) && ok;
    ok = checkDrawableLoads(logger, "IconSnowflake", Rez.Drawables.IconSnowflake) && ok;
    ok = checkDrawableLoads(logger, "IconTemperatureHalf", Rez.Drawables.IconTemperatureHalf) && ok;
    ok = checkDrawableLoads(logger, "IconGauge", Rez.Drawables.IconGauge) && ok;
    ok = checkDrawableLoads(logger, "IconFire", Rez.Drawables.IconFire) && ok;
    ok = checkDrawableLoads(logger, "IconMessage", Rez.Drawables.IconMessage) && ok;
    ok = checkDrawableLoads(logger, "IconStairs", Rez.Drawables.IconStairs) && ok;
    ok = checkDrawableLoads(logger, "IconStopwatch", Rez.Drawables.IconStopwatch) && ok;
    ok = checkDrawableLoads(logger, "IconPersonRunning", Rez.Drawables.IconPersonRunning) && ok;
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

(:test)
function testTrickResourcesSurviveHideShowCycle(logger as Test.Logger) as Boolean {
    // Regression test for a real on-device crash: onHide() nulls mTricks
    // (and the other resource caches) but onShow() didn't reload them, so
    // any background/foreground cycle short of full sleep -- a notification,
    // a widget glance -- crashed the watch face on its next trick or field
    // draw. mTricks is used here since it's reachable without a Dc.
    var view = new DogAnimationExperimentView();
    var ok = true;
    view.onShow(); // initial launch
    view.onHide(); // background: frees resources
    view.onShow(); // foreground again: must reload them
    try {
        view.startRandomTrick();
    } catch (ex) {
        logger.debug("startRandomTrick threw after a hide/show cycle: " + ex.getErrorMessage());
        ok = false;
    }
    view.onHide(); // stop the timer startRandomTrick() started
    return ok;
}

(:test)
function testReloadBreedDoesNotThrow(logger as Test.Logger) as Boolean {
    var view = new DogAnimationExperimentView();
    var ok = true;
    try {
        view.reloadBreed();
    } catch (ex) {
        logger.debug("reloadBreed threw: " + ex.getErrorMessage());
        ok = false;
    }
    return ok;
}
