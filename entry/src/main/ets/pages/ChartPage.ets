import { router, componentSnapshot } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ChartResult, ChartOptions, StarInfo, StarCell, cloneOptions } from '../engine/ZiWeiEngine';
import { buildFromInputs, ChartInputs as Inputs, sanFangSiZheng } from '../engine/BuildHelper';
import { loadOptions, loadGeo, GeoInfo } from '../engine/OptionsStore';
import { COLORS, TIAN_GAN, DI_ZHI } from '../engine/Constants';
import { SI_HUA_NAN_PAI, SI_HUA_ZHONG_ZHOU } from '../engine/AnXingTables';
import { hant } from '../engine/TextConv';
import { ChartShare, ShareResult } from '../share/ChartShare';

// 分享用的临时图文件名：固定名（每次覆盖），不会在沙箱里堆垃圾；
// 导出用的图带时间戳，用完即删（见 exportImage 的 finally）。
const SHARE_TMP_NAME = 'ziwei-share';

// 四化徽章色：禄朱砂/权黛蓝/科竹青/忌绛紫
function sihuaBadgeColor(s: string): string {
  if (s === '禄') { return COLORS.red; }
  if (s === '权') { return COLORS.blue; }
  if (s === '科') { return COLORS.green; }
  return COLORS.purple;
}

// 四化浅底色（横条底）
function sihuaSoftColor(s: string): string {
  if (s === '禄') { return COLORS.primarySoft; }
  if (s === '权') { return COLORS.blueSoft; }
  if (s === '科') { return COLORS.greenSoft; }
  return COLORS.purpleSoft;
}

// 宫位详情路由参数（ArkTS 不支持对象字面量类型，须显式声明 interface）
interface DetailParams {
  calendarType: string;
  gender: string;
  solarYear: number;
  solarMonth: number;
  solarDay: number;
  lunarYear: number;
  lunarMonth: number;
  lunarDay: number;
  isLeap: boolean;
  hour: number;
  minute: number;
  palaceIndex: number;
  currentAge: number;
}

// 环抱布局：地支→格子序号（Grid 4 列按行主序）
// 行0: 巳(0) 午(1) 未(2) 申(3)；行1: 辰(4) [中5,6] 酉(7)
// 行2: 卯(8) [中9,10] 戌(11)；行3: 寅(12) 丑(13) 子(14) 亥(15)
const BRANCH_TO_SLOT: Record<string, number> = {
  '巳': 0, '午': 1, '未': 2, '申': 3,
  '辰': 4, '酉': 7,
  '卯': 8, '戌': 11,
  '寅': 12, '丑': 13, '子': 14, '亥': 15
};

// 槽位 → Grid 跨度（中宫占 5/6/9/10 四槽，在第 5 槽跨 2×2）
const CENTER_SLOT = 5;

@Entry
@Component
struct ChartPage {
  @State chart: ChartResult | null = null;
  @State inputs: Inputs | null = null;
  @State opts: ChartOptions | null = null;
  @State longitude: number | null = null;
  @State viewMode: string = 'native'; // 'native' | 'liunian' | 'daxian'
  // 默认流年/年龄按「打开应用时的年份」与出生年动态推算（虚岁），
  // 原先写死 2026 / 39：跨年后默认流年与年龄都会过期，且与用户实际生辰无关。
  @State liuNianYear: number = 0;
  @State currentAge: number = 0;
  @State @Watch('onSelectedPalaceChange') selectedPalace: number = 0;
  @State infoText: ResourceStr = '';
  @State toastText: ResourceStr = '';
  @State showYearPicker: boolean = false;
  @State slots: (StarCell | null)[] = [];

  // 16 槽布局更新
  private updateSlots(): void {
    if (this.chart) {
      this.buildSlots(this.chart);
    }
  }

  private toastTimer: number = -1;

  // 三方四正连线的画布上下文。Canvas 一旦 onReady，ctx 就能读到自身宽高，
  // 之后换选中宫只要 clearRect + 重画，不必再等一次布局。
  private triadCtx: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private triadReady: boolean = false;
  // 画布尺寸在 onReady 时量一次并缓存，重绘时一律用缓存值：
  // onReady 是唯一能确保「已经量到真实尺寸」的时刻，之后不再去读
  // ctx.width/height（读到的值不可靠，读到 0 会让 clearRect 清不动、
  // 直接 return，画布就永远停在首次绘制的内容）。
  private triadW: number = 0;
  private triadH: number = 0;

  // 选中宫变了就重画连线（@Watch 的「事件回调 + 重绘」链路是必须的，
  // 那条连线不是声明式 UI，不会随状态自动刷新）
  onSelectedPalaceChange(): void {
    if (this.triadReady) {
      this.drawTriad();
    }
  }

  // TextPicker 数据源缓存：range 数组若在 build() 里每次新建，
  // TextPicker 会认为数据源变化而重排，滚动时表现为抖动。只生成一次。
  private cachedYearStrings: string[] = [];
  private cachedAgeStrings: string[] = [];

  aboutToAppear(): void {
    // 无参拉起时 getParams() 返回 undefined，直接取下标会抛 TypeError → 白屏
    const params = (router.getParams() ?? {}) as Record<string, Object>;
    const inp: Inputs = {
      calendarType: (params['calendarType'] as string) || 'solar',
      gender: (params['gender'] as string) || '男',
      solarYear: Number(params['solarYear'] ?? 0),
      solarMonth: Number(params['solarMonth'] ?? 0),
      solarDay: Number(params['solarDay'] ?? 0),
      lunarYear: Number(params['lunarYear'] ?? 0),
      lunarMonth: Number(params['lunarMonth'] ?? 0),
      lunarDay: Number(params['lunarDay'] ?? 0),
      isLeap: (params['isLeap'] as boolean) ?? false,
      hour: Number(params['hour'] ?? 18),
      minute: Number(params['minute'] ?? 0)
    };
    this.inputs = inp;
    // 流年默认取今年；年龄按虚岁（今年 - 出生年 + 1）
    const nowYear: number = new Date().getFullYear();
    this.liuNianYear = nowYear;
    const birthYear: number = inp.calendarType === 'lunar' ? inp.lunarYear : inp.solarYear;
    this.currentAge = birthYear > 0 ? nowYear - birthYear + 1 : nowYear - 1987 + 1;
    if (this.currentAge < 1) {
      this.currentAge = 1;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    loadOptions(ctx).then((o: ChartOptions) => {
      this.opts = o;
      return loadGeo(ctx);
    }).then((g: GeoInfo) => {
      this.longitude = (this.opts && this.opts.useTrueSolarTime) ? g.longitude : null;
      // 同步重建：此处已在异步回调中，不占首帧。原 setTimeout(100ms) 反而让
      // errorView 先渲染 100ms 再硬切成 chartView，制造一次闪烁。
      this.rebuild();
    }).catch(() => {
      this.infoText = $r('app.string.err_settings');
    });
    // 华为分享：把「取当前命盘图」的能力交给分享模块（碰一碰/抓一抓时按需取图）；
    // 同时用当前窗口注册碰一碰监听。失败不阻断排盘，静默降级为「只能用按钮分享」。
    ChartShare.setProvider((): Promise<string | null> => this.captureChartJpeg(SHARE_TMP_NAME));
    ChartShare.registerKnock(ctx).catch(() => {
    });
  }

  // 离开页面：解绑碰一碰，清掉分享用的临时图（导出图在 exportImage 里已自删）
  aboutToDisappear(): void {
    ChartShare.unregisterKnock();
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      fileIo.unlinkSync(ctx.filesDir + '/' + SHARE_TMP_NAME + '.jpg');
    } catch (e) {
    }
  }

  rebuild(): void {
    if (!this.inputs || !this.opts) {
      return;
    }
    const merged: ChartOptions = cloneOptions(this.opts);
    merged.liuNianYear = this.viewMode === 'liunian' ? this.liuNianYear : null;
    merged.currentAge = this.viewMode === 'daxian' ? this.currentAge : null;
    const c = buildFromInputs({
      calendarType: this.inputs.calendarType,
      gender: this.inputs.gender,
      solarYear: this.inputs.solarYear,
      solarMonth: this.inputs.solarMonth,
      solarDay: this.inputs.solarDay,
      lunarYear: this.inputs.lunarYear,
      lunarMonth: this.inputs.lunarMonth,
      lunarDay: this.inputs.lunarDay,
      isLeap: this.inputs.isLeap,
      hour: this.inputs.hour,
      minute: this.inputs.minute,
      options: merged,
      longitude: this.longitude
    });
    if (c) {
      const isFirstBuild: boolean = (this.chart === null);
      this.chart = c;
      // 只在首次排盘时定位到命宫。切换视图/改流年/改年龄都会走到 rebuild()，
      // 原先无条件重置为命宫，选中态被硬拉回去，看起来就是「闪跳」。
      if (isFirstBuild || this.selectedPalace < 0 || this.selectedPalace >= c.palaces.length) {
        this.selectedPalace = c.mingGongIndex;
      }
      this.updateSlots();
      // Toast 只在首次排盘提示一次；原先每次 rebuild 都弹，切视图时反复闪。
      if (isFirstBuild) {
        this.showToast($r('app.string.toast_selected',
          hant(c.palaces[c.mingGongIndex].palaceName), c.palaces[c.mingGongIndex].dizhi));
      }
    } else {
      this.infoText = $r('app.string.err_date_range');
    }
  }

  // 按地支把 12 宫填进 16 槽
  private buildSlots(c: ChartResult): void {
    const arr: (StarCell | null)[] = [];
    for (let i = 0; i < 16; i++) {
      arr.push(null);
    }
    for (const p of c.palaces) {
      const slot = BRANCH_TO_SLOT[p.dizhi];
      if (slot !== undefined) {
        arr[slot] = p;
      }
    }
    this.slots = arr;
  }

  private showToast(msg: ResourceStr): void {
    this.toastText = msg;
    if (this.toastTimer >= 0) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => {
      this.toastText = '';
    }, 2200);
  }

  // 三方四正缓存：原先每帧对 12 个宫格各构造 3 次数组（36 次/帧），
  // 选中宫不变时结果恒定，没必要重算。
  private sfzCacheKey: number = -1;
  private sfzCache: number[] = [];

  private isSanFang(idx: number): boolean {
    if (this.sfzCacheKey !== this.selectedPalace) {
      this.sfzCacheKey = this.selectedPalace;
      this.sfzCache = sanFangSiZheng(this.selectedPalace);
    }
    return this.sfzCache.indexOf(idx) >= 0;
  }

  private palaceBorderColor(idx: number): string {
    if (!this.chart) {
      return COLORS.borderLight;
    }
    if (idx === this.selectedPalace) {
      return COLORS.primary;
    }
    if (this.isSanFang(idx)) {
      return COLORS.blue;
    }
    return COLORS.borderLight;
  }

  // 干序 → 四化文案（如 庚 → 太阳禄、武曲权、太阴科、天同忌），随派别选项
  private siHuaText(gan: number): string {
    const table = this.opts && this.opts.siHuaStyle === 'ZhongZhou' ? SI_HUA_ZHONG_ZHOU : SI_HUA_NAN_PAI;
    const row = table[((gan % 10) + 10) % 10];
    return row[0] + '禄、' + row[1] + '权、' + row[2] + '科、' + row[3] + '忌';
  }

  // 公历年 → 干支（甲子纪年）
  private yearGzOf(y: number): string {
    return TIAN_GAN[(((y - 4) % 10) + 10) % 10] + DI_ZHI[(((y - 4) % 12) + 12) % 12];
  }

  private buildMarkdown(): string {
    const c = this.chart;
    if (!c) {
      return '';
    }
    // 导出文案走多语言资源；星名/宫名等盘面术语是引擎数据，由 hant() 显示层转换
    const rm = getContext(this).resourceManager;
    let s: string = rm.getStringSync($r('app.string.md_title').id) + '\n\n';
    s += rm.getStringSync($r('app.string.md_gender').id, c.gender) + '\n';
    const mm: string = c.minute < 10 ? '0' + c.minute : `${c.minute}`;
    s += rm.getStringSync($r('app.string.md_clock').id,
      `${c.solarYear}-${c.solarMonth}-${c.solarDay} ${c.hour}:${mm}`) + '\n';
    if (c.useTrueSolar && c.longitude != null) {
      const th: number = Math.floor(c.trueSolarHour);
      const tm: number = Math.round((c.trueSolarHour - th) * 60);
      const tms: string = tm < 10 ? '0' + tm : `${tm}`;
      const lon: string = `${Math.round(c.longitude * 100) / 100}`;
      s += rm.getStringSync($r('app.string.md_truesolar').id,
        `${c.solarYear}-${c.solarMonth}-${c.solarDay} ${th}:${tms}`, lon) + '\n';
    }
    const leap: string = c.isLeap ? rm.getStringSync($r('app.string.leap_suffix').id) : '';
    s += rm.getStringSync($r('app.string.md_lunar').id,
      `${c.lunarYear}`, `${c.lunarMonth}`, `${c.lunarDay}`, leap) + '\n';
    s += rm.getStringSync($r('app.string.md_sizhu').id, c.jieQiSiZhu) + '\n';
    s += rm.getStringSync($r('app.string.md_sizhu_fn').id, c.feiJieQiSiZhu) + '\n';
    s += rm.getStringSync($r('app.string.md_ju').id, c.wuXingJu, c.mingZhu, c.shenZhu) + '\n';
    if (c.douJunIndex >= 0) {
      s += rm.getStringSync($r('app.string.md_doujun').id, c.palaces[c.douJunIndex].dizhi) + '\n';
    }
    s += rm.getStringSync($r('app.string.md_minggong').id,
      c.palaces[c.mingGongIndex].palaceName, c.palaces[c.mingGongIndex].dizhi) + '\n';
    s += rm.getStringSync($r('app.string.md_shengong').id,
      c.palaces[c.shenGongIndex].palaceName, c.palaces[c.shenGongIndex].dizhi) + '\n';
    if (c.laiYinIndex >= 0) {
      s += rm.getStringSync($r('app.string.md_laiyin').id,
        c.palaces[c.laiYinIndex].palaceName, c.palaces[c.laiYinIndex].ganzhi) + '\n';
    }
    s += rm.getStringSync($r('app.string.md_ziwei').id,
      c.palaces[c.ziWeiIndex].palaceName, c.palaces[c.tianFuIndex].palaceName) + '\n\n';
    s += rm.getStringSync($r('app.string.md_palaces').id) + '\n\n';
    for (const p of c.palaces) {
      s += `### ${p.palaceName}（${p.dizhi} ${p.ganzhi}）\n`;
      if (p.mainStars.length) {
        s += rm.getStringSync($r('app.string.md_main').id) + p.mainStars.map((st: StarInfo) =>
          st.name + (st.brightness ? `(${st.brightness})` : '')
          + (st.sihua ? `[生年${st.sihua}]` : '')
          + (st.selfSihua ? `[${st.selfSihua}]` : '')).join('、') + '\n';
      }
      if (p.auxStars.length) {
        s += rm.getStringSync($r('app.string.md_aux').id) + p.auxStars.map((st: StarInfo) =>
          st.name + (st.sihua ? `[生年${st.sihua}]` : '')
          + (st.selfSihua ? `[${st.selfSihua}]` : '')).join('、') + '\n';
      }
      if (this.opts && this.opts.showShenSha && p.shenSha.length) {
        s += rm.getStringSync($r('app.string.md_shensha').id) + p.shenSha.join('、') + '\n';
      }
      if (p.changSheng) {
        s += rm.getStringSync($r('app.string.md_twelve').id, p.changSheng, p.boShi, p.jiangQian, p.suiQian) + '\n';
      }
      if (p.daXianStart >= 0) {
        s += rm.getStringSync($r('app.string.md_daxian').id, `${p.daXianStart}`, `${p.daXianEnd}`) + '\n';
      }
      if (p.xiaoXianAges.length) {
        s += rm.getStringSync($r('app.string.md_xiaoxian').id,
          p.xiaoXianAges.map((a: number) => `${a}`).join(',')) + '\n';
      }
      if (p.liuNianAges.length) {
        s += rm.getStringSync($r('app.string.md_ln_ages').id,
          p.liuNianAges.map((a: number) => `${a}`).join(',')) + '\n';
      }
      const die: string = p.dieGongAges.length
        ? p.dieGongAges.map((a: number) => `${a}虚岁(${c.lunarYear + a - 1})`).join('、')
        : rm.getStringSync($r('app.string.md_none').id);
      s += rm.getStringSync($r('app.string.md_diegong').id, die) + '\n';
      s += '\n';
    }
    // 大限流年信息（12 大限 × 各 10 流年，文墨天机同口径）
    s += rm.getStringSync($r('app.string.md_dx_title').id) + '\n\n';
    const sorted: StarCell[] = [...c.palaces].sort((a: StarCell, b: StarCell) => a.daXianStart - b.daXianStart);
    let no: number = 0;
    for (const p of sorted) {
      if (p.daXianStart < 0) {
        continue;
      }
      no++;
      const y0: number = c.lunarYear + p.daXianStart - 1;
      const y1: number = c.lunarYear + p.daXianEnd - 1;
      s += `### ` + rm.getStringSync($r('app.string.md_dx_header').id,
        `${no}`, p.palaceName, p.ganzhi, `${y0}`, `${y1}`, `${p.daXianStart}`, `${p.daXianEnd}`) + '\n';
      const dStem: number = TIAN_GAN.indexOf(p.stem.charAt(0));
      s += rm.getStringSync($r('app.string.md_dx_sihua').id, this.siHuaText(dStem)) + '\n';
      for (let a = p.daXianStart; a <= p.daXianEnd; a++) {
        const yr: number = c.lunarYear + a - 1;
        const lnBranch: number = (((yr - 4) % 12) + 12) % 12;
        const lp: StarCell | undefined = c.palaces.find((pp: StarCell) => pp.dizhi === DI_ZHI[lnBranch]);
        const lnGan: number = (((yr - 4) % 10) + 10) % 10;
        s += rm.getStringSync($r('app.string.md_ln_line').id,
          `${yr}`, this.yearGzOf(yr), `${a}`, lp ? lp.ganzhi : '-', this.siHuaText(lnGan)) + '\n';
      }
      s += '\n';
    }
    return hant(s);
  }

  // 复制排盘文本到剪贴板。按钮文案即「复制信息」，与这里的实际动作对齐
  // （旧文案叫「导出信息」，暗示导出文件，与剪贴板行为不符）。
  // ★setData 是异步的：必须 await，否则失败被静默吞掉——表现为弹「已复制」
  //   但剪贴板是空的（实测踩过）。导出文案带 120 流年后体积大，更要等写完再报成功。
  private async copyInfo(): Promise<void> {
    if (!this.chart) {
      return;
    }
    const md: string = this.buildMarkdown();
    try {
      const pb: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, md);
      await pb.setData(data);
      this.showToast($r('app.string.copy_ok'));
    } catch (e) {
      this.showToast($r('app.string.copy_fail'));
    }
  }

  // 盘面截图 → JPEG → 沙箱文件，返回路径。导出与分享共用这一段。
  // 截图层（id=chartRoot）本身就不含底部留白，直接拍即可，无需改动任何样式。
  // 失败返回 null，由调用方决定提示什么。
  private async captureChartJpeg(fileBaseName: string): Promise<string | null> {
    if (!this.chart) {
      return null;
    }
    let pm: image.PixelMap | null = null;
    const packer: image.ImagePacker = image.createImagePacker();
    const ctx = getContext(this) as common.UIAbilityContext;
    try {
      pm = await componentSnapshot.get('chartRoot');
      const opt: image.PackingOption = { format: 'image/jpeg', quality: 96 };
      const buf: ArrayBuffer = await packer.packing(pm, opt);
      const path: string = ctx.filesDir + '/' + fileBaseName + '.jpg';
      const f = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(f.fd, buf);
      fileIo.closeSync(f);
      return path;
    } catch (e) {
      return null;
    } finally {
      if (pm !== null) {
        pm.release();
      }
      packer.release();
    }
  }

  // 分享命盘图：拉起系统分享面板（华为分享/加密分享/碰一碰都由面板提供）。
  // 「加密分享可禁止截图」是系统面板自带的通道（ShareAbilityName.ENCRYPT），
  // 应用侧不需要写任何加密或防截屏代码 —— 命盘属半隐私内容，交给系统更稳。
  private async shareChart(): Promise<void> {
    if (!this.chart) {
      return;
    }
    const path: string | null = await this.captureChartJpeg(SHARE_TMP_NAME);
    if (!path) {
      this.showToast($r('app.string.share_toast_nocontent'));
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const title: string = ctx.resourceManager.getStringSync($r('app.string.app_name').id);
    const r: ShareResult = await ChartShare.shareImage(ctx, title);
    if (r === ShareResult.UNSUPPORTED) {
      this.showToast($r('app.string.share_toast_unsupported'));
    } else if (r === ShareResult.FAILED) {
      this.showToast($r('app.string.share_toast_fail'));
    }
  }

  // 导出图片：盘面截图 → JPEG → 沙箱临时文件 → 系统「保存到相册」对话框。
  // 用 showAssetsCreationDialog 而不是申请相册写权限：不弹权限申请，存不存由用户
  // 在系统对话框里定，保住「全程离线、数据不出本机」的定位。
  //
  // ★这个接口只返回一个「已授权的空文件 URI」，它不会把源文件复制过去。必须由
  //   应用自己把内容写进目标 URI，否则表现是：对话框正常弹出、点了允许、甚至连
  //   返回的 URI 都拿到了，但相册里什么都没有（官方「答开发者问」写得很明确，
  //   本工程实测踩到过 —— 上一版就是只弹框没写入）。
  private async exportImage(): Promise<void> {
    if (!this.chart) {
      return;
    }
    const ctx = getContext(this) as common.UIAbilityContext;
    const name: string = 'ziwei-chart-' + Date.now().toString();
    let path: string = '';
    try {
      const p: string | null = await this.captureChartJpeg(name);
      if (!p) {
        this.showToast($r('app.string.save_fail'));
        return;
      }
      path = p;
      const cfg: photoAccessHelper.PhotoCreationConfig = {
        title: name,
        fileNameExtension: 'jpg',
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      const ph = photoAccessHelper.getPhotoAccessHelper(ctx);
      const uris: string[] = await ph.showAssetsCreationDialog([fileUri.getUriFromPath(path)], [cfg]);
      if (uris.length === 0) {
        // 用户在系统对话框里取消了
        this.showToast($r('app.string.save_cancel'));
        return;
      }
      // 把沙箱里的图真正写进系统给的目标 URI —— 少了这一步，相册里不会出现图片。
      const src = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const des = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY);
      fileIo.copyFileSync(src.fd, des.fd);
      fileIo.closeSync(src);
      fileIo.closeSync(des);
      this.showToast($r('app.string.save_ok'));
    } catch (e) {
      this.showToast($r('app.string.save_fail'));
    } finally {
      // 临时文件只在导出过程中用得着，进相册后立刻删除，免得沙箱里越攒越多
      if (path.length > 0) {
        try {
          fileIo.unlinkSync(path);
        } catch (e) {
        }
      }
    }
  }

  private openDetail(idx: number): void {
    const i = this.inputs;
    if (!i) {
      return;
    }
    const params: DetailParams = {
      calendarType: i.calendarType,
      gender: i.gender,
      solarYear: i.solarYear,
      solarMonth: i.solarMonth,
      solarDay: i.solarDay,
      lunarYear: i.lunarYear,
      lunarMonth: i.lunarMonth,
      lunarDay: i.lunarDay,
      isLeap: i.isLeap,
      hour: i.hour,
      minute: i.minute,
      palaceIndex: idx,
      currentAge: this.currentAge
    };
    router.pushUrl({ url: 'pages/DetailPage', params: params });
  }

  // 双击宫格：未选中→选中；已选中→进详情
  private onCellClick(p: StarCell): void {
    if (this.selectedPalace === p.palaceIndex) {
      this.openDetail(p.palaceIndex);
    } else {
      this.selectedPalace = p.palaceIndex;
      this.showToast($r('app.string.toast_selected', hant(p.palaceName), p.dizhi));
    }
  }

  // 当前视图的四化（生年/流年/大限）。
  // 引擎里 siHua 是「星名→禄权科忌」（siHua[row[0]]='禄'），供星曜徽章查自己化什么；
  // 底部四化横条要按「禄/权/科/忌→星名」反查，原先直接用引擎记录反着查，
  // 四个格子永远落到 '—'，界面上四化横条形同虚设。
  private activeSiHuaDisplay(): Record<string, string> {
    const c = this.chart;
    if (!c) {
      return {};
    }
    let src: Record<string, string>;
    if (this.viewMode === 'liunian' && c.liuNianSiHua) {
      src = c.liuNianSiHua;
    } else if (this.viewMode === 'daxian' && c.daXianSiHua) {
      src = c.daXianSiHua;
    } else {
      src = c.siHua;
    }
    const out: Record<string, string> = {};
    const keys: string[] = ['禄', '权', '科', '忌'];
    for (const k of keys) {
      out[k] = '—';
    }
    const stars = Object.keys(src);
    for (const star of stars) {
      const badge: string = src[star];
      if (badge && out[badge] === '—') {
        out[badge] = star;
      }
    }
    return out;
  }

  @Builder
  errorView() {
    Column() {
      Text(this.infoText).fontSize(16).fontColor(COLORS.error).margin(24)
      Button($r('app.string.back')).onClick(() => router.back())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  // 四化徽章
  @Builder
  sihuaBadge(s: string) {
    Text(s)
      .fontSize(9)
      .fontColor(Color.White)
      .backgroundColor(sihuaBadgeColor(s))
      .borderRadius(3)
      .padding({ left: 2.5, right: 2.5 })
      .margin({ left: 2 })
  }

  // 单宫格。
  // 不接收 chart 参数：@Builder 按值传参是首帧快照，rebuild() 换盘后快照里的
  // mingGong/shenGong 徽章还是旧盘指向。改为内部直读 this.chart。
  @Builder
  palaceCell(p: StarCell) {
    Column({ space: 2 }) {
      Row() {
        Text(hant(p.palaceName)).fontSize(11.5).fontWeight(FontWeight.Bold).fontColor(COLORS.textSecondary)
        Text(p.dizhi).fontSize(10.5).fontColor(COLORS.textMuted).margin({ left: 3 }).lineHeight(14)
        Text(p.stem).fontSize(10).fontColor(COLORS.accent).margin({ left: 2 }).lineHeight(13.5)
        Blank()
        if (p.daXianStart >= 0) {
          Text(`${p.daXianStart}-${p.daXianEnd}`)
            .fontSize(10)
            .fontColor(this.viewMode === 'daxian' ? COLORS.primary : COLORS.textMuted)
            .lineHeight(13.5)
        }
      }
      .width('100%')

      // 中间可变内容包一层 Scroll：宫格可用高有限，开关全开时内容可能超过格子，
      // 滚动而非裁切，保证命/身徽章与神煞始终可见（不撑变形盘面）。
      Scroll() {
        Column({ space: 2 }) {
          ForEach(p.mainStars, (s: StarInfo) => {
            Row() {
              Text(hant(s.name)).fontSize(12).fontWeight(FontWeight.Medium).fontColor(COLORS.text)
              if (s.brightness && (!this.opts || this.opts.showBrightness)) {
                Text(hant(s.brightness)).fontSize(10).fontColor(COLORS.textMuted).margin({ left: 1 }).lineHeight(13.5)
              }
              if (s.sihua) {
                this.sihuaBadge(hant(s.sihua))
              }
            }
          }, (s: StarInfo) => s.name + p.palaceIndex.toString())

          if (p.mainStars.length === 0) {
            Text($r('app.string.empty_palace')).fontSize(10.5).fontColor(COLORS.textMuted).lineHeight(14)
          }

          if (p.auxStars.length > 0) {
            Text(hant(p.auxStars.map((s: StarInfo) => s.name + (s.sihua ? s.sihua : '')).join(' ')))
              .fontSize(10.5)
              .fontColor(COLORS.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(14)
          }

          if (this.opts && this.opts.showShenSha && p.shenSha.length > 0) {
            Text(hant(p.shenSha.join(' ')))
              .fontSize(10)
              .fontColor(COLORS.textMuted)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(13.5)
          }

          if (this.viewMode === 'liunian' && p.liuNianName) {
            Text($r('app.string.liunian_cell', hant(p.liuNianName))).fontSize(10).fontColor(COLORS.blue).lineHeight(13.5)
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollable(ScrollDirection.Vertical)

      Row() {
        Blank()
        if (this.chart && p.palaceIndex === this.chart.mingGongIndex) {
          Text($r('app.string.badge_ming'))
            .fontSize(10).fontColor(Color.White)
            .backgroundColor(COLORS.primary)
            .borderRadius(3)
            .padding({ left: 3, right: 3 })
        }
        if (this.chart && p.palaceIndex === this.chart.shenGongIndex) {
          Text($r('app.string.badge_shen'))
            .fontSize(10).fontColor(Color.White)
            .backgroundColor(COLORS.green)
            .borderRadius(3)
            .padding({ left: 3, right: 3 })
            .margin({ left: 2 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding({ left: 5, right: 5, top: 5, bottom: 4 })
    .border({
      width: this.selectedPalace === p.palaceIndex ? 1.5 : (this.isSanFang(p.palaceIndex) ? 1.5 : 1),
      color: this.palaceBorderColor(p.palaceIndex)
    })
    .borderRadius(8)
    .backgroundColor(this.chart && p.palaceIndex === this.chart.mingGongIndex ? COLORS.primarySoft :
      (this.isSanFang(p.palaceIndex) ? COLORS.blueSoft : COLORS.surface))
    .shadow(this.selectedPalace === p.palaceIndex
      ? { radius: 8, color: COLORS.primaryGlowSoft, offsetX: 0, offsetY: 0 }
      : { radius: 4, color: COLORS.shadowSoft, offsetX: 0, offsetY: 1 })
    // 双击才生效：盘面是主要阅读区，单击误触会把选中态带走（三方四正高亮
    // 与连线跟着跳），所以把触发门槛提到双击。
    .gesture(TapGesture({ count: 2 }).onAction(() => {
      this.onCellClick(p);
    }))
  }

  // 中宫文案（@Builder 内不能声明局部变量，组合文案统一放这里）
  private centerMingShen(c: ChartResult): string {
    return hant(getContext(this).resourceManager.getStringSync(
      $r('app.string.center_zhuzhu').id, c.mingZhu, c.shenZhu));
  }

  private centerZiWeiTianFu(c: ChartResult): string {
    return getContext(this).resourceManager.getStringSync($r('app.string.center_ziwei').id,
      c.palaces[c.ziWeiIndex].dizhi, c.palaces[c.tianFuIndex].dizhi);
  }

  private centerDaXian(c: ChartResult): string {
    return hant(getContext(this).resourceManager.getStringSync(
      $r('app.string.center_daxian').id, c.palaces[c.daXianMingIndex].palaceName));
  }

  private centerLiuNian(c: ChartResult): string {
    return hant(getContext(this).resourceManager.getStringSync($r('app.string.center_liunian').id,
      `${c.liuNianYear}`, c.palaces[c.liuNianMingIndex].palaceName));
  }

  // 概要卡文案
  private pillarsLine(c: ChartResult): string {
    return getContext(this).resourceManager.getStringSync($r('app.string.pillars_line').id,
      c.yearGanZhi, c.monthGanZhi, c.dayGanZhi, c.hourGanZhi);
  }

  private summaryLine(c: ChartResult): string {
    const rm = getContext(this).resourceManager;
    const leap: string = c.isLeap ? rm.getStringSync($r('app.string.leap_suffix').id) : '';
    return hant(rm.getStringSync($r('app.string.chart_summary').id,
      `${c.lunarYear}`, `${c.lunarMonth}`, `${c.lunarDay}`, leap, c.wuXingJu, c.mingZhu, c.shenZhu));
  }

  private chipText(key: Resource, value: string): string {
    return getContext(this).resourceManager.getStringSync(key.id, value);
  }

  // 视图切换旁的年份/年龄 chip（年龄带「岁」单位，走资源，英文下不带）
  private ageChip(): string {
    return getContext(this).resourceManager.getStringSync(
      $r('app.string.age_val').id, `${this.currentAge}`);
  }

  // 中宫（跨 2×2）。
  // 不接收 chart 参数：@Builder 按值传参拿到的是首帧快照，切大限/流年视图后
  // this.chart 已换新对象，快照里的 viewMode 判断虽读 this，但 c.daXianMingIndex
  // 等字段还是旧的，导致中宫永远停在排盘口径行。改为内部直读 this.chart。
  @Builder
  centerCell() {
    Column({ space: 2 }) {
      Text($r('app.string.seal_zi'))
        .fontSize(14)
        .fontColor(COLORS.goldInk)
        .fontWeight(FontWeight.Bold)
        .width(30)
        .height(30)
        .textAlign(TextAlign.Center)
        .borderRadius(15)
        .backgroundColor(COLORS.primary)
        .margin({ bottom: 3 })
      if (this.chart) {
        Text(hant(this.chart.wuXingJu))
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.text)
          .letterSpacing(2)
        Text(this.centerMingShen(this.chart))
          .fontSize(10.5)
          .fontColor(COLORS.textSecondary)
        Text(`${this.chart.yearGanZhi} ${this.chart.monthGanZhi}\n${this.chart.dayGanZhi} ${this.chart.hourGanZhi}`)
          .fontSize(10)
          .fontColor(COLORS.textMuted)
          .textAlign(TextAlign.Center)
          .margin({ top: 3 })
        if (this.viewMode === 'daxian' && this.chart.daXianMingIndex >= 0) {
          Text(this.centerDaXian(this.chart))
            .fontSize(10)
            .fontColor(COLORS.primary)
            .margin({ top: 2 })
        } else if (this.viewMode === 'liunian' && this.chart.liuNianYear != null) {
          Text(this.centerLiuNian(this.chart))
            .fontSize(10)
            .fontColor(COLORS.blue)
            .margin({ top: 2 })
        } else {
          Text(this.centerZiWeiTianFu(this.chart))
            .fontSize(10)
            .fontColor(COLORS.textMuted)
            .margin({ top: 2 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(COLORS.centerBg)
    .border({ width: 1.5, color: COLORS.primary })
    .borderRadius(10)
  }

  // 视图分段项
  @Builder
  segOption(key: string, label: Resource) {
    Text(label)
      .fontSize(13)
      .textAlign(TextAlign.Center)
      .padding({ top: 15, bottom: 15 })
      .borderRadius(9)
      .backgroundColor(this.viewMode === key ? COLORS.surface : COLORS.surfaceAlt)
      .fontColor(this.viewMode === key ? COLORS.primary : COLORS.textSecondary)
      .fontWeight(this.viewMode === key ? FontWeight.Bold : FontWeight.Normal)
      .layoutWeight(1)
      .onClick(() => {
        if (this.viewMode !== key) {
          this.viewMode = key;
          this.rebuild();
        }
      })
  }

  // 命盘主视图。
  // 不接收 chart 参数：@Builder 按值传参拿到的是首帧快照，切换视图/改流年/改年龄
  // 后 this.chart 已是新生成的对象，快照仍指旧盘——表现为「切到大限视图，中宫
  // 还显示紫微天府那行」。概要卡/宫位/中宫全部直读 this.chart（@State）。
  @Builder
  chartView() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // 截图层：用 layoutWeight 占满「扣除操作栏」之后的剩余高度，天然不含底部
        // 留白。导出时因此不需要再改 padding —— 旧写法在导出前把 padding 从 70
        // 改成 0，内容区高度瞬间跳变 70vp，界面会明显"拉伸一下"，拍完又弹回来。
        Column() {
        // ===== 概要卡 =====
        Column({ space: 5 }) {
          // 返回按钮：盘面页在 2in1 设备上没有系统返回手势，必须有显式入口
          Row() {
            Text('‹')
              .fontSize(24)
              .fontColor(COLORS.textSecondary)
              .width(44)
              .height(44)
              .textAlign(TextAlign.Center)
              .borderRadius(22)
              .backgroundColor(COLORS.surface)
              .border({ width: 1, color: COLORS.borderLight })
              .onClick(() => router.back())
            Blank()
          }
          .width('100%')
          .margin({ bottom: 2 })

          Row({ space: 8 }) {
            Text(this.pillarsLine(this.chart as ChartResult))
              .fontSize(15).fontWeight(FontWeight.Bold).fontColor(COLORS.text)
            Text((this.chart as ChartResult).gender === '男' ? $r('app.string.male') : $r('app.string.female'))
              .fontSize(10)
              .fontColor(COLORS.blue)
              .backgroundColor(COLORS.blueSoft)
              .borderRadius(9)
              .padding({ left: 8, right: 8, top: 1.5, bottom: 1.5 })
          }
          .width('100%')

          Text(this.summaryLine(this.chart as ChartResult))
            .fontSize(11.5)
            .fontColor(COLORS.textSecondary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Row({ space: 6 }) {
            Text(this.chipText($r('app.string.chip_ming'), (this.chart as ChartResult).palaces[(this.chart as ChartResult).mingGongIndex].dizhi))
              .fontSize(10.5)
              .fontColor(COLORS.primary)
              .backgroundColor(COLORS.primarySoft)
              .borderRadius(10)
              .padding({ left: 9, right: 9, top: 2.5, bottom: 2.5 })
            Text(this.chipText($r('app.string.chip_shen'), (this.chart as ChartResult).palaces[(this.chart as ChartResult).shenGongIndex].dizhi))
              .fontSize(10.5)
              .fontColor(COLORS.green)
              .backgroundColor(COLORS.greenSoft)
              .borderRadius(10)
              .padding({ left: 9, right: 9, top: 2.5, bottom: 2.5 })
            Text(this.chipText($r('app.string.chip_ziwei'), (this.chart as ChartResult).palaces[(this.chart as ChartResult).ziWeiIndex].dizhi))
              .fontSize(10.5)
              .fontColor(COLORS.blue)
              .backgroundColor(COLORS.blueSoft)
              .borderRadius(10)
              .padding({ left: 9, right: 9, top: 2.5, bottom: 2.5 })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(13)
        .borderRadius(16)
        .backgroundColor(COLORS.surface)
        .shadow({ radius: 8, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
        .margin({ left: 14, right: 14, top: 10 })

        // ===== 视图切换（分段） =====
        Row() {
          Row() {
            this.segOption('native', $r('app.string.native_view'))
            this.segOption('daxian', $r('app.string.daxian_view'))
            this.segOption('liunian', $r('app.string.liunian_view'))
          }
          .backgroundColor(COLORS.surfaceAlt)
          .borderRadius(12)
          .padding(4)
          .layoutWeight(1)

          // 常驻渲染、用 Hidden 占位：原先 if 条件渲染会在 native↔流年/大限
          // 切换时插入/移除这个 chip，layoutWeight(1) 的分段控件宽度随之跳变，
          // 三个 tab 整体抽动一下。Hidden 占位则宽度恒定。
          // 固定宽度是顺带修掉「2026」与「39岁」字数不同导致的二次宽度抖动。
          Text(this.viewMode === 'liunian' ? `${this.liuNianYear}` : this.ageChip())
            .fontSize(12)
            .fontColor(COLORS.primary)
            .backgroundColor(COLORS.primarySoft)
            .borderRadius(13)
            .height(26)
            .width(58)
            .textAlign(TextAlign.Center)
            .margin({ left: 8 })
            .visibility(this.viewMode === 'native' ? Visibility.Hidden : Visibility.Visible)
            .onClick(() => { this.showYearPicker = true; })
        }
        .width('100%')
        .margin({ left: 14, right: 14, top: 10 })

        // ===== 12 宫环抱盘面（Grid 4×4，中宫跨 2×2） =====
        Text($r('app.string.tap_hint'))
          .fontSize(10.5)
          .fontColor(COLORS.textMuted)
          .letterSpacing(1)
          .width('100%')
          .margin({ left: 18, right: 14, top: 10 })
        // 盘面 + 三方四正连线叠层。连线压在 Grid 之上（PC 版也是压在盘面上），
        // 但设成不参与命中测试，双击宫格的判定不受影响。
        // 连线用 Canvas 画：onReady 里量一次尺寸（跨层百分比拿不到具体值），
        // 之后选中宫一变就 clearRect + 重画。
        Stack() {
          this.chartGrid()
          // 连线层：压在盘面之上，但不吃触摸事件，双击宫格照常。
          Canvas(this.triadCtx)
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
            .onReady(() => {
              this.triadW = this.triadCtx.width;
              this.triadH = this.triadCtx.height;
              this.triadReady = true;
              this.drawTriad();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ left: 14, right: 14, top: 10 })

        // ===== 四化横条 =====
        Row({ space: 6 }) {
          ForEach(['禄', '权', '科', '忌'], (k: string) => {
            Row({ space: 4 }) {
              Text(hant(k))
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(sihuaBadgeColor(k))
              Text(hant(this.activeSiHuaDisplay()[k] ?? '—'))
                .fontSize(11)
                .fontColor(COLORS.textSecondary)
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding({ top: 6, bottom: 6 })
            .borderRadius(9)
            .backgroundColor(sihuaSoftColor(k))
          }, (k: string) => k)
        }
        .width('100%')
        .margin({ left: 14, right: 14, top: 10 })
      }
      // 截图范围 = chartRoot（id 就挂在这一层）：只含概要卡、视图切换、盘面与四化横条。
      // ★操作栏必须与截图层「同父、且在正常文档流里」：截图层 layoutWeight(1) 吃掉
      //   除操作栏以外的全部高度，操作栏自己占住底部 70vp（44 按钮高 + 12 上边距 +
      //   14 下边距），两者是兄弟、互不覆盖。早先把操作栏放在外层 Stack 里当浮层，
      //   盘面会一直伸到按钮底下被压住，导出的图也多出一条被按钮盖住的内容。
      // ★导出时不再需要改任何尺寸：历史写法在导出前把 chartRoot 的 padding 从 70
      //   改成 0，内容区高度瞬间跳变 70vp，界面会明显「拉伸一下」，拍完又弹回来。
      //   现在截图层的尺寸在导出前后完全一致，天然没有这一步。
      //
      // ★必须显式给背景色：这层自身没有底色（页面底色在外层 Stack 上），不给的话
      //   截图是透明底，编码成 JPEG 后透明区会变黑，导出图跟界面完全不是一个色。
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(COLORS.bg)
        .id('chartRoot')

        // ===== 操作 =====
        // 四颗等宽：复制信息 / 导出图片 / 分享 是浅底次要动作，查看详情是朱砂实心主入口。
        // 从三颗加到四颗后字号收到 12.5，否则 4 字标签在窄屏上会被压到换行。
        Row({ space: 8 }) {
          Button($r('app.string.copy_info'))
            .backgroundColor(COLORS.primarySoft).fontColor(COLORS.primary)
            .border({ width: 1, color: COLORS.primaryGlow })
            .borderRadius(22)
            .height(44)
            .layoutWeight(1)
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.copyInfo();
            })
          Button($r('app.string.export_image'))
            .backgroundColor(COLORS.primarySoft).fontColor(COLORS.primary)
            .border({ width: 1, color: COLORS.primaryGlow })
            .borderRadius(22)
            .height(44)
            .layoutWeight(1)
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.exportImage();
            })
          Button($r('app.string.share_chart'))
            .backgroundColor(COLORS.primarySoft).fontColor(COLORS.primary)
            .border({ width: 1, color: COLORS.primaryGlow })
            .borderRadius(22)
            .height(44)
            .layoutWeight(1)
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .onClick(() => {
              this.shareChart();
            })
          Button($r('app.string.detail'))
            .backgroundColor(COLORS.primary).fontColor(COLORS.goldInk)
            .borderRadius(22)
            .height(44)
            .layoutWeight(1)
            .fontSize(13.5)
            .fontWeight(FontWeight.Medium)
            .shadow({ radius: 14, color: COLORS.primaryGlow, offsetX: 0, offsetY: 4 })
            .onClick(() => {
              this.openDetail(this.selectedPalace);
            })
        }
        .width('100%')
        .margin({ left: 14, right: 14, top: 12, bottom: 14 })
      }
      .width('100%')
      .height('100%')

      // ===== Toast =====
      if (this.toastText !== '') {
        Text(this.toastText)
          .fontSize(12)
          .fontColor(COLORS.bg)
          .backgroundColor(COLORS.toastBg)
          .borderRadius(18)
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .margin({ bottom: 76 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.bg)
  }

  // 12 宫环抱盘面（Grid 4×4，中宫跨 2×2）。抽成独立 @Builder 是为了能在
  // chartView 里被 Stack 包住、叠三方四正连线；外边距移到外层 Stack 上，
  // 这样 Stack 的尺寸就等于盘面本身，连线锚点算的是同一套坐标。
  @Builder
  chartGrid() {
    Grid() {
      GridItem() {
        this.cellOrBlank(0)
      }
      GridItem() {
        this.cellOrBlank(1)
      }
      GridItem() {
        this.cellOrBlank(2)
      }
      GridItem() {
        this.cellOrBlank(3)
      }
      GridItem() {
        this.cellOrBlank(4)
      }
      GridItem() {
        this.centerCell()
      }
      .columnStart(1).columnEnd(2).rowStart(1).rowEnd(2)
      GridItem() {
        this.cellOrBlank(7)
      }
      GridItem() {
        this.cellOrBlank(8)
      }
      GridItem() {
        this.cellOrBlank(11)
      }
      GridItem() {
        this.cellOrBlank(12)
      }
      GridItem() {
        this.cellOrBlank(13)
      }
      GridItem() {
        this.cellOrBlank(14)
      }
      GridItem() {
        this.cellOrBlank(15)
      }
    }
    .columnsTemplate('1fr 1fr 1fr 1fr')
    .rowsTemplate('1fr 1fr 1fr 1fr')
    .columnsGap(5)
    .rowsGap(5)
    .width('100%')
    .height('100%')
  }

  // 三方四正连线锚点：0=选中宫，1=+4 财帛，2=+8 官禄，3=+6 迁移。
  // 偏移量与 PC 版 DrawTriad 一致，但注意这里的「index」是**宫序**
  // （palaces[] 以命宫为 0，见引擎 placeMain：pIdx = (星地支 - 命宫地支) mod 12），
  // 不是地支序号。原先当地支序号直接查 DI_ZHI，等于把整个三角绕命宫转了一个角度，
  // 画出来的四正全错宫（实测选中官禄时画到了申子辰）。
  // 正确走法：宫序 → 取该宫的地支 → 映射到盘面槽位。
  private triadAnchor(sel: number, i: number, w: number, h: number): number[] {
    const c = this.chart;
    if (!c) {
      return [-1, -1];
    }
    const offs: number[] = [0, 4, 8, 6];
    const palace = c.palaces[(sel + offs[i]) % 12];
    if (!palace) {
      return [-1, -1];
    }
    const slot: number | undefined = BRANCH_TO_SLOT[palace.dizhi];
    if (slot === undefined) {
      return [-1, -1];
    }
    const gap = 5;
    const cw = (w - gap * 3) / 4;
    const ch = (h - gap * 3) / 4;
    return [(slot % 4) * (cw + gap) + cw / 2, Math.floor(slot / 4) * (ch + gap) + ch / 2];
  }

  // 三方四正连线：三合那三条边用黛蓝、对宫那一条用朱砂，半透明压在盘面上。
  // 结构照 PC 版（三合 2.5px / 对宫 2.0px / opacity .55），色值换成本工程色板，
  // 与既有的「三方四正」高亮底色同源，不引入新的视觉语言。
  //
  // 用 Canvas 而不是 Shape+Polyline：Shape 的 viewPort 只吃具体数值吃不了百分比，
  // 量—画的时序一旦踩空就整条线不出现；Canvas 在 onReady 里就能读到自身宽高。
  private drawTriad(): void {
    const ctx = this.triadCtx;
    const w: number = this.triadW > 0 ? this.triadW : ctx.width;
    const h: number = this.triadH > 0 ? this.triadH : ctx.height;
    ctx.clearRect(0, 0, w, h);
    if (!this.chart || w <= 0 || h <= 0) {
      return;
    }
    const pts: number[][] = [];
    for (let i = 0; i < 4; i++) {
      const p = this.triadAnchor(this.selectedPalace, i, w, h);
      if (p[0] < 0) {
        return;
      }
      pts.push(p);
    }
    ctx.globalAlpha = 0.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    // 三合三角（命→财→官→命）
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    ctx.lineTo(pts[1][0], pts[1][1]);
    ctx.lineTo(pts[2][0], pts[2][1]);
    ctx.closePath();
    ctx.strokeStyle = COLORS.blue;
    ctx.lineWidth = 2;
    ctx.stroke();
    // 对宫线（命→迁）
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    ctx.lineTo(pts[3][0], pts[3][1]);
    ctx.strokeStyle = COLORS.red;
    ctx.lineWidth = 1.8;
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  // 槽位渲染（null 为中宫占位，渲染空）
  @Builder
  cellOrBlank(slotIdx: number) {
    if (this.slots.length > slotIdx && this.slots[slotIdx] !== null && this.chart) {
      this.palaceCell(this.slots[slotIdx] as StarCell)
    }
  }

  build() {
    // 根容器必须自带底色：chart 尚未就绪时渲染的是 errorView，
    // 原先只有 chartView 有 backgroundColor，errorView 阶段整页透明，
    // 露出窗口底色（白）再切成米白，就是进命盘页时的那一下闪白。
    // 外层 Row 居中 + maxWidth 适配平板/2in1，手机端宽度 <480 不受影响。
    Row() {
      Stack() {
      if (this.chart) {
        this.chartView()
      } else if (this.infoText !== '') {
        // 真出错（rebuild 里设置过错误文案）才显示错误视图 + 返回按钮
        this.errorView()
      } else {
        // 排盘计算中（preferences 首读 + 首帧之间）：只给加载圈。
        // 之前直接渲染 errorView，infoText 为空时页面上只有一颗孤零零的
        // 返回按钮——就是「点开始排盘到出现排盘界面之前」那个返回按钮。
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(COLORS.primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      // ===== 流年年份 / 年龄选择弹层 =====
      if (this.showYearPicker) {
        Column() {
          Blank()
          Column() {
            Row() {
              Text(this.viewMode === 'liunian' ? $r('app.string.year_label') : $r('app.string.age_label'))
                .fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLORS.text)
              Blank()
              Text($r('app.string.close'))
                .fontSize(14).fontColor(COLORS.textMuted)
                .onClick(() => { this.showYearPicker = false; })
            }
            .width('100%')
            .margin({ bottom: 8 })

            if (this.viewMode === 'liunian') {
              TextPicker({ range: this.yearStrings(), selected: this.yearIndex() })
                .backgroundColor(COLORS.bg)
                .onChange((value: string | string[], index: number | number[]) => {
                  const i: number = (typeof index === 'number') ? index : 0;
                  const arr = this.yearRange();
                  if (i >= 0 && i < arr.length) {
                    this.liuNianYear = arr[i];
                  }
                })
                .layoutWeight(1)
            } else {
              TextPicker({ range: this.ageStrings(), selected: this.ageIndex() })
                .backgroundColor(COLORS.bg)
                .onChange((value: string | string[], index: number | number[]) => {
                  const i: number = (typeof index === 'number') ? index : 0;
                  const arr = this.ageRange();
                  if (i >= 0 && i < arr.length) {
                    this.currentAge = arr[i];
                  }
                })
                .layoutWeight(1)
            }

            Button($r('app.string.confirm'))
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor(COLORS.goldInk)
              .backgroundColor(COLORS.primary)
              .borderRadius(22)
              .shadow({ radius: 14, color: COLORS.primaryGlow, offsetX: 0, offsetY: 4 })
              .margin({ top: 12 })
              .onClick(() => {
                this.showYearPicker = false;
                this.rebuild();
              })
          }
          .width('100%')
          .padding(16)
          .height(340)
          .backgroundColor(COLORS.surface)
          .borderRadius({ topLeft: 20, topRight: 20 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.scrim)
        .onClick(() => { this.showYearPicker = false; })
      }
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 480 })
    .backgroundColor(COLORS.bg)
  }
  .width('100%')
  .height('100%')
  .justifyContent(FlexAlign.Center)
  .backgroundColor(COLORS.bg)
}

  private yearRange(): number[] {
    const a: number[] = [];
    for (let y = 1950; y <= 2070; y++) { a.push(y); }
    return a;
  }

  private ageRange(): number[] {
    const a: number[] = [];
    for (let y = 1; y <= 120; y++) { a.push(y); }
    return a;
  }

  private yearStrings(): string[] {
    if (this.cachedYearStrings.length === 0) {
      const out: string[] = [];
      for (const n of this.yearRange()) {
        out.push(n.toString());
      }
      this.cachedYearStrings = out;
    }
    return this.cachedYearStrings;
  }

  private yearIndex(): number {
    const idx = this.yearRange().indexOf(this.liuNianYear);
    return idx >= 0 ? idx : 0;
  }

  private ageStrings(): string[] {
    if (this.cachedAgeStrings.length === 0) {
      const out: string[] = [];
      for (const n of this.ageRange()) {
        out.push(n.toString());
      }
      this.cachedAgeStrings = out;
    }
    return this.cachedAgeStrings;
  }

  private ageIndex(): number {
    const idx = this.ageRange().indexOf(this.currentAge);
    return idx >= 0 ? idx : 0;
  }
}
