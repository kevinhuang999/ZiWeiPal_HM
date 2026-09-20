// 华为分享：命盘图加密分享 / 碰一碰（Tap to Transfer）/ 远程直达
//
// ★ 零成本、零新增权限：
//   - 分享面板是系统能力（ShareKit），应用侧只需把数据装进 SharedData 交给 ShareController。
//   - 「加密分享（禁止截图）」是系统面板自带的通道（ShareAbilityName.ENCRYPT），
//     用户在面板里选「加密分享」即可，应用不需要写任何加密/防截屏代码。
//   - 「碰一碰 / 远程直达」走 harmonyShare.on('knockShare' | 'gesturesShare')，
//     同样不需要额外权限。
//   - 「多人分享」由面板的收件人多选完成，应用侧无需适配。
import { window } from '@kit.ArkUI';
import { systemShare, harmonyShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// 图片的 UDMF 统一数据类型
const UTD_IMAGE = 'general.image';
const LABEL_IMAGE = 'IMAGE';

export enum ShareResult {
  OK = 0,
  DISMISSED = 1,   // 面板被关掉（含用户取消）
  UNSUPPORTED = 2, // 设备无分享能力
  FAILED = 3
}

// 取当前命盘图（沙箱 jpg 路径）。由页面注入——分享模块不关心图是怎么来的。
export type ChartFileProvider = () => Promise<string | null>;

export class ChartShare {
  private static provider: ChartFileProvider | null = null;
  private static controller: systemShare.ShareController | null = null;
  private static windowId: number = -1;
  private static knockOn: boolean = false;

  /** 页面在 aboutToAppear 里注册取图函数 */
  static setProvider(p: ChartFileProvider): void {
    ChartShare.provider = p;
  }

  private static async currentUri(): Promise<string | null> {
    const p = ChartShare.provider;
    if (!p) {
      return null;
    }
    try {
      const path: string | null = await p();
      if (!path || path.length === 0) {
        return null;
      }
      return fileUri.getUriFromPath(path);
    } catch (e) {
      return null;
    }
  }

  private static buildData(uri: string, title: string): systemShare.SharedData {
    const record: systemShare.SharedRecord = {
      utd: UTD_IMAGE,
      uri: uri,
      title: title,
      label: LABEL_IMAGE
    };
    return new systemShare.SharedData(record);
  }

  /**
   * 拉起系统分享面板分享命盘图。
   * previewMode 用 DETAIL（图片/视频推荐），面板里自带「加密分享」「华为分享」「保存到相册」等通道。
   */
  static async shareImage(ctx: common.UIAbilityContext, title: string): Promise<ShareResult> {
    const uri: string | null = await ChartShare.currentUri();
    if (!uri) {
      return ShareResult.FAILED;
    }
    try {
      const data: systemShare.SharedData = ChartShare.buildData(uri, title);
      const ctrl: systemShare.ShareController = new systemShare.ShareController(data);
      ChartShare.controller = ctrl;
      const opts: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      };
      await ctrl.show(ctx, opts);
      // 面板已拉起即算成功；用户是否真的发出去了由 shareCompleted 事件统计
      ctrl.on('shareCompleted', (r: systemShare.ShareOperationResult) => {
        hilog.info(DOMAIN, 'testTag', 'shareCompleted via %{public}s', r.targetAbilityInfo.name);
      });
      return ShareResult.OK;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'share failed: %{public}s', JSON.stringify(err));
      if (err && err.code === 801) {
        return ShareResult.UNSUPPORTED;
      }
      return ShareResult.FAILED;
    }
  }

  /**
   * 注册碰一碰 / 抓一抓。两个设备的应用都在前台时，轻触即在接收端弹出。
   * 取图是异步的，回调体内用 then/catch 承接，不阻塞系统回调。
   */
  static async registerKnock(ctx: common.UIAbilityContext): Promise<boolean> {
    if (ChartShare.knockOn) {
      return true;
    }
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      ChartShare.windowId = win.getWindowProperties().id;
      const cap: harmonyShare.SendCapabilityRegistry = { windowId: ChartShare.windowId };
      const cb = (target: harmonyShare.SharableTarget): void => {
        ChartShare.serveKnock(target).catch(() => {
        });
      };
      harmonyShare.on('knockShare', cap, cb);
      harmonyShare.on('gesturesShare', cap, cb);
      ChartShare.knockOn = true;
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'registerKnock failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  // 被碰/被抓时把当前命盘图交给对方；没有盘就明确回绝，避免对方一直转圈
  private static async serveKnock(target: harmonyShare.SharableTarget): Promise<void> {
    const uri: string | null = await ChartShare.currentUri();
    if (!uri) {
      await target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR);
      return;
    }
    await target.share(ChartShare.buildData(uri, '紫微命盘'));
  }

  /** 页面 onPageHide / aboutToDisappear 时解绑，防止跨页面重复注册 */
  static unregisterKnock(): void {
    if (!ChartShare.knockOn) {
      return;
    }
    try {
      harmonyShare.off('knockShare');
      harmonyShare.off('gesturesShare');
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'unregisterKnock failed: %{public}s', JSON.stringify(e));
    }
    ChartShare.knockOn = false;
  }
}
