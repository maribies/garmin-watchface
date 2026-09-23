import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class DogAnimationExperimentApp extends Application.AppBase {

    private var mView as DogAnimationExperimentView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        mView = new DogAnimationExperimentView();
        return [ mView ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.reloadBreed();
        }
        WatchUi.requestUpdate();
    }

}

function getApp() as DogAnimationExperimentApp {
    return Application.getApp() as DogAnimationExperimentApp;
}