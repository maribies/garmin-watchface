import Toybox.Lang;
import Toybox.Test;

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
