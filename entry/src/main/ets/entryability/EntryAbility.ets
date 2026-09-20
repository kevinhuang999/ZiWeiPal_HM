import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 先设置颜色模式，再设置状态栏（避免状态栏闪烁）
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 国风浅色为刻意设计：跟随系统深色时未适配的深底资源会导致观感错乱，强制浅色
      try {
        // 检查设备类型，2合1设备不支持getContext，跳过状态栏设置
        const context = this.context as Context;
        if (context && context.resourceManager) {
          const deviceType = context.resourceManager.getDeviceCapabilitySync().deviceType;
          if (deviceType !== resourceManager.DeviceType.DEVICE_TYPE_2IN1) {
            windowStage.getMainWindowSync().setWindowSystemBarProperties({
              statusBarContentColor: '#2C1810',  // 更深的朱砂色，对比度更好
              isStatusBarLightIcon: false
            });
          }
        }
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to set status bar. Cause: %{public}s', JSON.stringify(err));
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}