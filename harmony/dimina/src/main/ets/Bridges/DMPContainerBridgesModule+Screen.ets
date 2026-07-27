import { DMPMap } from '../Utils/DMPMap';
import { DMPContainerBridgesModule } from './DMPContainerBridgesModule';
import { DMPBridgeCallback, DMPBridgeCallbackType } from './DMPTSUtil';
import { DMPApp } from '../DApp/DMPApp';
import { DMPLogger } from '../EventTrack/DMPLogger';
import { Tags } from '../EventTrack/Tags';

const ON_USER_CAPTURE_SCREEN = 'onUserCaptureScreen';
const OFF_USER_CAPTURE_SCREEN = 'offUserCaptureScreen';

/** Screen module that bridges the system screenshot event to the service layer. */
export class DMPContainerBridgesModuleScreen extends DMPContainerBridgesModule {
  private jsCallbacks: Map<string, DMPBridgeCallback> = new Map();
  private screenshotListener: (() => void) | null = null;

  getExportMethods(): Array<string> {
    return [ON_USER_CAPTURE_SCREEN, OFF_USER_CAPTURE_SCREEN];
  }

  onUserCaptureScreen(data: DMPMap, callback: DMPBridgeCallback) {
    const callbackId = data.getString('callbackId') ?? data.getString('success');
    if (!callbackId) {
      this.invokeFailureCallback(callback, null, `${ON_USER_CAPTURE_SCREEN}:fail`);
      return;
    }

    this.jsCallbacks.clear();
    this.jsCallbacks.set(callbackId, callback);
    if (this.screenshotListener) {
      return;
    }

    const listener = () => this.notifyCaptured();
    try {
      const mainWindow = DMPApp.getWindowStage().getMainWindowSync();
      mainWindow.on('screenshot', listener);
      this.screenshotListener = listener;
      DMPLogger.d(Tags.BRIDGE, `${ON_USER_CAPTURE_SCREEN}: screenshot listener registered`);
    } catch (err) {
      this.jsCallbacks.delete(callbackId);
      DMPLogger.e(Tags.BRIDGE, `${ON_USER_CAPTURE_SCREEN}: register screenshot listener failed: ${err}`);
      this.invokeFailureCallback(callback, null, `${ON_USER_CAPTURE_SCREEN}:fail`);
    }
  }

  offUserCaptureScreen(data: DMPMap, _callback: DMPBridgeCallback) {
    const callbackId = data.getString('callbackId');
    if (callbackId) {
      this.jsCallbacks.delete(callbackId);
    } else {
      this.jsCallbacks.clear();
    }
    if (this.jsCallbacks.size === 0) {
      this.releaseSystemListener();
    }
  }

  dispose(): void {
    this.jsCallbacks.clear();
    this.releaseSystemListener();
  }

  private notifyCaptured() {
    const result = new DMPMap();
    this.jsCallbacks.forEach((callback: DMPBridgeCallback) => {
      callback(result, DMPBridgeCallbackType.Success);
    });
  }

  private releaseSystemListener() {
    if (!this.screenshotListener) {
      return;
    }
    try {
      DMPApp.getWindowStage().getMainWindowSync().off('screenshot', this.screenshotListener);
      DMPLogger.d(Tags.BRIDGE, `${OFF_USER_CAPTURE_SCREEN}: screenshot listener unregistered`);
    } catch (err) {
      DMPLogger.e(Tags.BRIDGE, `${OFF_USER_CAPTURE_SCREEN}: unregister screenshot listener failed: ${err}`);
    }
    this.screenshotListener = null;
  }
}
