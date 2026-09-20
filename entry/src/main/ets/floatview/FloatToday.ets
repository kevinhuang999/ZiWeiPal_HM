// 闪控球 ↔ 闪控窗：今天流日运势的悬浮窗控制器（HarmonyOS 7 / API 26）
//
// ★★ 上线前必读（这是本功能唯一的门槛，不是代码问题）：
//   floatView.start() 需要 ohos.permission.FLOAT_VIEW
//   floatingBall.startFloatingBall() 需要 ohos.permission.USE_FLOAT_BALL
//   这两个权限在 SDK 的 PermissionDefinitions.json 里都是
//     "availableLevel": "system_basic"（系统基础级，普通应用不能直接声明）
//     "provisionEnable": true（可走 Profile 的 ACL 受限权限申请）
//   也就是说：必须在 AGC 申请 ACL 并由华为审核通过、把权限写进 release Profile，
//   才能在 module.json5 里打开 requestPermissions 里的那两行。
//   没批就打开 → AGC「申请 Profile」直接失败，整个上架流程卡死。
//
//   代码侧已完整实现，开关见本文件 isEnabled()：常量 GATE_ACL_APPROVED 置 true 并
//   在 module.json5 里解除注释后即可生效。未开启时所有入口只提示，不发权限请求。
import { floatView, floatingBall, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

// 悬浮窗页面（须已在 resources/base/profile/main_pages.json 里登记）
const FLOAT_PAGE = 'pages/FloatPage';

// ★ ACL 闸门：华为批下受限权限前置 false。改 true 时必须同步解开 module.json5
//   里 requestPermissions 的两行注释，否则 start() 会返回 201（权限校验失败）。
const GATE_ACL_APPROVED: boolean = false;

// 启动结果，交给调用方决定弹什么文案（不在这里弹 toast，保持纯逻辑）
export enum FloatStartResult {
  OK = 0,
  UNSUPPORTED = 1,      // 设备/系统不支持闪控球或闪控窗
  NEED_ACL = 2,         // 受限权限没批（GATE_ACL_APPROVED=false）
  PERMISSION_DENIED = 3,// 权限被拒（201）
  ALREADY_RUNNING = 4,
  FAILED = 5
}

// 悬浮球上的标题/正文（≤64 字节，中文 3 字节/字，控制在 20 字内）
export interface BallText {
  title: string;
  content: string;
}

// 闪控球模板：常规态（圆角矩形）/ mini 态（横向条）
export enum FloatShape {
  NORMAL = 0,
  MINI = 1
}

function templateOf(shape: FloatShape): floatView.FloatViewTemplateType {
  return shape === FloatShape.MINI
    ? floatView.FloatViewTemplateType.HORIZONTAL_BAR
    : floatView.FloatViewTemplateType.ROUNDED_RECTANGLE;
}

export class FloatToday {
  private static fvc: floatView.FloatViewController | null = null;
  private static fbc: floatingBall.FloatingBallController | null = null;
  private static started: boolean = false;
  private static shape: FloatShape = FloatShape.NORMAL;

  // 入口统一问这里，别各页面自己判断，免得两处口径不一致
  static isEnabled(): boolean {
    return GATE_ACL_APPROVED;
  }

  static isRunning(): boolean {
    return FloatToday.started;
  }

  static currentShape(): FloatShape {
    return FloatToday.shape;
  }

  // 设备是否具备能力。canIUse 之外还要问系统开关，用户可能自己在系统设置里关了
  private static supported(): boolean {
    try {
      if (!canIUse('SystemCapability.Window.SessionManager')) {
        return false;
      }
      return floatView.isFloatViewEnabled() && floatingBall.isFloatingBallEnabled();
    } catch (e) {
      return false;
    }
  }

  /**
   * 按模板档位取尺寸——「窗随屏变」：不写死宽高，由系统给的上下限 + 比例区间推出来。
   * 手机取窄档、平板/2in1 取宽档，模板换 mini 态时重新取一次。
   */
  private static pickSize(shape: FloatShape, ctx: common.UIAbilityContext): window.Size {
    const tpl: floatView.FloatViewTemplateType = templateOf(shape);
    const limits: floatView.FloatViewLimits = floatView.getFloatViewLimits(tpl);
    // 设备类型只管「往大取还是往小取」，真正的边界一律以系统 limits 为准
    let isLarge: boolean = false;
    try {
      const dt = ctx.resourceManager.getDeviceCapabilitySync().deviceType;
      isLarge = (dt === resourceManager.DeviceType.DEVICE_TYPE_TABLET)
        || (dt === resourceManager.DeviceType.DEVICE_TYPE_2IN1);
    } catch (e) {
      isLarge = false;
    }
    // 竖版比例 1:1.25；平板取宽档
    const ratio: number = isLarge ? 1.05 : 1.25;
    let w: number = limits.maxSize.width;
    let h: number = Math.round(w * ratio);
    if (h > limits.maxSize.height) {
      h = limits.maxSize.height;
      w = Math.round(h / ratio);
    }
    if (w > limits.maxSize.width) { w = limits.maxSize.width; }
    if (w < limits.minSize.width) { w = limits.minSize.width; }
    if (h < limits.minSize.height) { h = limits.minSize.height; }
    // 比例夹进系统区间（多档时取最宽的可接受范围）
    const rl: floatView.RatioLimit[] = limits.ratioLimits;
    if (rl && rl.length > 0) {
      let minR: number = rl[0].minRatio;
      let maxR: number = rl[0].maxRatio;
      for (const it of rl) {
        if (it.minRatio < minR) { minR = it.minRatio; }
        if (it.maxRatio > maxR) { maxR = it.maxRatio; }
      }
      const r: number = w / h;
      if (r < minR) {
        w = Math.round(h * minR);
      } else if (r > maxR) {
        h = Math.round(w / maxR);
      }
    }
    return { width: w, height: h };
  }

  private static ballParams(text: BallText): floatingBall.FloatingBallParams {
    return {
      template: floatingBall.FloatingBallTemplate.NORMAL,
      title: text.title,
      content: text.content,
      backgroundColor: '#F2E2DA',
      titleColor: '#9B2E23',
      contentColor: '#6B5D4F'
    };
  }

  /**
   * 创建 + 绑定 + 启动。绑定后点闪控球可展开成闪控窗，闪控窗左上角最小化按钮收回成球。
   * @param ctx  UIAbilityContext
   * @param text 球面文案（球态下显示，展开后由 FloatPage 自绘）
   */
  static async start(ctx: common.UIAbilityContext, text: BallText): Promise<FloatStartResult> {
    if (!GATE_ACL_APPROVED) {
      return FloatStartResult.NEED_ACL;
    }
    if (!FloatToday.supported()) {
      return FloatStartResult.UNSUPPORTED;
    }
    if (FloatToday.started) {
      return FloatStartResult.ALREADY_RUNNING;
    }
    try {
      const fvc: floatView.FloatViewController = await floatView.create({
        context: ctx,
        templateType: templateOf(FloatToday.shape),
        isConfirmOnClose: false
      });
      const fbc: floatingBall.FloatingBallController = await floatingBall.create({ context: ctx });
      await fvc.setUIContext(FLOAT_PAGE);
      // bind 要求两个控制器都还没 start，顺序不能换
      await floatView.bind(fvc, fbc, FloatToday.ballParams(text));
      await fvc.setWindowSize(FloatToday.pickSize(FloatToday.shape, ctx));
      FloatToday.fvc = fvc;
      FloatToday.fbc = fbc;
      // 先起闪控窗（展开态），用户点最小化再收回球——与「悬浮窗常驻」的诉求一致
      await fvc.start();
      FloatToday.started = true;
      return FloatStartResult.OK;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, 'testTag', 'floatView start failed: %{public}s', JSON.stringify(err));
      FloatToday.reset();
      if (err && err.code === 201) {
        return FloatStartResult.PERMISSION_DENIED;
      }
      if (err && err.code === 801) {
        return FloatStartResult.UNSUPPORTED;
      }
      return FloatStartResult.FAILED;
    }
  }

  // 常规态 / mini 态互切（两个标准模板 + 尺寸档位随模板重取）
  static async switchShape(shape: FloatShape, ctx: common.UIAbilityContext): Promise<boolean> {
    const fvc = FloatToday.fvc;
    if (!fvc || !FloatToday.started) {
      return false;
    }
    try {
      await fvc.switchTemplate({
        templateType: templateOf(shape),
        size: FloatToday.pickSize(shape, ctx)
      });
      FloatToday.shape = shape;
      return true;
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'switchTemplate failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }

  // 让主窗口回到前台（悬浮窗页面里点「回到主界面」用）
  static async restoreMain(): Promise<void> {
    const fvc = FloatToday.fvc;
    if (!fvc) {
      return;
    }
    try {
      await fvc.restoreMainWindow();
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'restoreMainWindow failed: %{public}s', JSON.stringify(e));
    }
  }

  // 停任一个：绑定态下会同时销毁闪控窗与闪控球
  static async stop(): Promise<void> {
    const fvc = FloatToday.fvc;
    const fbc = FloatToday.fbc;
    if (fvc) {
      try {
        await fvc.stop();
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'floatView stop failed: %{public}s', JSON.stringify(e));
      }
    }
    if (fbc) {
      try {
        await fbc.stopFloatingBall();
      } catch (e) {
        hilog.error(DOMAIN, 'testTag', 'ball stop failed: %{public}s', JSON.stringify(e));
      }
    }
    FloatToday.reset();
  }

  private static reset(): void {
    if (FloatToday.fvc && FloatToday.fbc) {
      try {
        floatView.unbind(FloatToday.fvc, FloatToday.fbc).catch(() => {
        });
      } catch (e) {
      }
    }
    FloatToday.fvc = null;
    FloatToday.fbc = null;
    FloatToday.started = false;
  }
}
