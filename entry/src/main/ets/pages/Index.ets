import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { solar2lunar, lunar2solar } from '../engine/CalendarUtil';
import { hourName, COLORS } from '../engine/Constants';
import { ChartOptions, DEFAULT_OPTIONS, cloneOptions, trueSolarHourFor } from '../engine/ZiWeiEngine';
import { loadOptions, saveOptions, loadGeo, saveGeo, GeoInfo } from '../engine/OptionsStore';
import { GEO_CITIES, GeoCity } from '../engine/AnXingTables';
import { hant } from '../engine/TextConv';
import { FloatToday, FloatStartResult, BallText } from '../floatview/FloatToday';

// 生辰路由参数（ArkTS 不支持对象字面量类型，须显式声明 interface）
interface BirthParams {
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
}

// 最近排盘记录（ArkTS 须显式 interface）
interface RecentItem {
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
  label: string;
}

const RECENT_STORE = 'ziwei_recent';
const CN_NUM: string[] = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '十', '冬', '腊'];

// 农历日中文（初一…三十）
function lunarDayCn(d: number): string {
  const prefix: string[] = ['初', '十', '廿', '三'];
  const nums: string[] = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  if (d === 10) { return '初十'; }
  if (d === 20) { return '二十'; }
  if (d === 30) { return '三十'; }
  return prefix[Math.floor(d / 10)] + nums[(d % 10) - 1];
}

// 生辰编辑弹层字段
type EditField = 'none' | 'year' | 'month' | 'day' | 'hour' | 'minute';

@Entry
@Component
struct Index {
  @State calendarType: string = 'solar'; // 'solar' | 'lunar'
  @State gender: string = '男';
  @State year: number = 1987;
  @State month: number = 6;
  @State day: number = 1;
  @State hour: number = 18;
  @State minute: number = 0;
  @State isLeap: boolean = false;
  @State editField: EditField = 'none';
  @State hourShichen: string = '酉时';
  @State convertTip: string = '';
  @State convertFail: boolean = false;
  @State recents: RecentItem[] = [];
  // 排盘口径 + 出生地：既是首页表单里可直接改的项（真太阳时开关 / 出生地），
  // 也决定首页显示的时辰。开了真太阳时后命盘用的是修正后时辰，首页若仍按原始
  // 钟点显示，就会出现「首页写酉时、盘面按申时排」的不一致。
  @State opts: ChartOptions = DEFAULT_OPTIONS;
  @State longitude: number | null = null;
  @State city: string = '';
  @State showCity: boolean = false;
  @State cityKeyword: string = '';

  // 弹层轮盘数据源缓存：TextPicker 的 range 若在 build() 里每次新建数组，
  // 组件会判定数据源变化而重排，滚动时表现为抖动。字段不变就复用同一数组。
  private pickerRangeField: string = '';
  private pickerRangeCache: string[] = [];

  aboutToAppear(): void {
    this.refreshTip();
    this.loadRecents();
    // 读取排盘口径与出生地，既用于表单显示，也用于按真太阳时口径显示时辰
    const ctx = getContext(this) as common.UIAbilityContext;
    loadOptions(ctx).then((o: ChartOptions) => {
      this.opts = o;
      return loadGeo(ctx);
    }).then((g: GeoInfo) => {
      this.longitude = g.longitude;
      this.city = g.city;
      this.refreshTip();
    }).catch(() => {
    });
  }

  // 从设置页切语言返回时重算：convertTip 是 getStringSync 的结果缓存，
  // 框架的语言重建不会更新已经存进状态里的字符串
  onPageShow(): void {
    this.refreshTip();
  }

  // 历法换算提示：公历→农历 / 农历→公历；顺带刷新首页时辰
  private refreshTip(): void {
    this.convertFail = false;
    let solarY: number = this.year;
    let solarM: number = this.month;
    let solarD: number = this.day;
    const rm = getContext(this).resourceManager;
    if (this.calendarType === 'solar') {
      const r = solar2lunar(this.year, this.month, this.day);
      if (r) {
        this.convertTip = rm.getStringSync($r('app.string.tip_lunar').id,
          CN_NUM[r.lMonth - 1], lunarDayCn(r.lDay), r.gzYear);
      } else {
        this.convertTip = rm.getStringSync($r('app.string.err_solar2lunar').id);
        this.convertFail = true;
      }
    } else {
      const r = lunar2solar(this.year, this.month, this.day, this.isLeap);
      if (r) {
        this.convertTip = rm.getStringSync($r('app.string.tip_solar').id,
          `${r.solarYear}-${r.solarMonth}-${r.solarDay}`);
        solarY = r.solarYear;
        solarM = r.solarMonth;
        solarD = r.solarDay;
      } else {
        this.convertTip = rm.getStringSync($r('app.string.err_lunar_invalid').id);
        this.convertFail = true;
      }
    }
    // 时辰：日期无效时不换算；开了真太阳时且选过出生地，则与命盘页同一口径
    let shownHour: number = this.hour + this.minute / 60.0;
    if (!this.convertFail && this.opts.useTrueSolarTime && this.longitude != null) {
      shownHour = trueSolarHourFor(solarY, solarM, solarD, this.hour, this.minute, this.longitude);
    }
    this.hourShichen = hourName(shownHour);
  }

  // 换算提示 + 时辰：时辰并到农历年后面显示（原先是「历法」行最右侧的独立角标，
  // 换个位置更像一条完整的生辰描述）。换算失败时提示的是错误信息，不并时辰。
  private tipText(): string {
    if (this.convertFail) {
      return hant(this.convertTip);
    }
    return hant(this.convertTip + ' · ' + this.hourShichen);
  }

  // 改排盘口径：整个对象替换（不原地改字段），确保 @State 一定触发重渲染
  private setOpt(apply: (o: ChartOptions) => void): void {
    const next: ChartOptions = cloneOptions(this.opts);
    apply(next);
    this.opts = next;
    const ctx = getContext(this) as common.UIAbilityContext;
    saveOptions(ctx, next).catch(() => {
    });
    this.refreshTip();
  }

  private persistGeo(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    saveGeo(ctx, { longitude: this.longitude, city: this.city }).catch(() => {
    });
    this.refreshTip();
  }

  // 出生地副标题（经度）
  private geoText(): string {
    const rm = getContext(this).resourceManager;
    if (this.longitude == null) {
      return rm.getStringSync($r('app.string.geo_none').id);
    }
    return rm.getStringSync($r('app.string.geo_lon').id, this.longitude.toFixed(2));
  }

  private cityText(): string {
    if (this.city.length > 0) {
      return hant(this.city);
    }
    return getContext(this).resourceManager.getStringSync($r('app.string.choose').id);
  }

  // 筛选城市
  private filteredCities(): GeoCity[] {
    if (this.cityKeyword.length === 0) {
      return GEO_CITIES;
    }
    const out: GeoCity[] = [];
    for (const c of GEO_CITIES) {
      if (c.cn.indexOf(this.cityKeyword) >= 0 || c.en.toLowerCase().indexOf(this.cityKeyword.toLowerCase()) >= 0) {
        out.push(c);
      }
    }
    return out;
  }

  // 最近排盘：日期部分（按当前语言现算，切语言后旧记录跟着变）
  private recentDate(it: RecentItem): string {
    const rm = getContext(this).resourceManager;
    if (it.calendarType === 'solar') {
      return hant(`${it.solarYear}-${it.solarMonth}-${it.solarDay}`);
    }
    return hant(rm.getStringSync($r('app.string.lunar_label').id,
      `${it.lunarYear}`, `${it.lunarMonth}`, `${it.lunarDay}`));
  }

  private loadRecents(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(ctx, RECENT_STORE).then((pf: preferences.Preferences) => {
      const raw = pf.getSync('items', '[]') as string;
      try {
        const arr = JSON.parse(raw) as RecentItem[];
        const out: RecentItem[] = [];
        for (const it of arr) {
          out.push(it);
        }
        this.recents = out;
      } catch (e) {
        this.recents = [];
      }
    }).catch(() => {
    });
  }

  // 清空最近排盘
  private saveRecentsClear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(ctx, RECENT_STORE).then((pf: preferences.Preferences) => {
      pf.putSync('items', '[]');
      return pf.flush();
    }).catch(() => {
    });
  }

  private saveRecent(p: BirthParams): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    const item: RecentItem = {
      calendarType: p.calendarType,
      gender: p.gender,
      solarYear: p.solarYear,
      solarMonth: p.solarMonth,
      solarDay: p.solarDay,
      lunarYear: p.lunarYear,
      lunarMonth: p.lunarMonth,
      lunarDay: p.lunarDay,
      isLeap: p.isLeap,
      hour: p.hour,
      minute: p.minute,
      // label 只当去重键（语言无关）；界面显示文案由 recentDate() 按当前语言现算，
      // 否则切语言后旧记录会一直停留在保存时那门语言。
      label: `${p.calendarType}|${p.solarYear}-${p.solarMonth}-${p.solarDay}`
        + `|${p.lunarYear}-${p.lunarMonth}-${p.lunarDay}|${p.isLeap}`
        + `|${p.hour}:${p.minute}|${p.gender}`
    };
    // 去重（同生辰同性别同时辰）后置顶，最多 3 条
    const list: RecentItem[] = [item];
    for (const it of this.recents) {
      if (list.length >= 3) { break; }
      if (it.label !== item.label) {
        list.push(it);
      }
    }
    this.recents = list;
    preferences.getPreferences(ctx, RECENT_STORE).then((pf: preferences.Preferences) => {
      pf.putSync('items', JSON.stringify(list));
      return pf.flush();
    }).catch(() => {
    });
  }

  private goChart(p: BirthParams): void {
    this.saveRecent(p);
    router.pushUrl({ url: 'pages/ChartPage', params: p });
  }

  // 今日运势悬浮窗（闪控球 ↔ 闪控窗）。
  // ★该能力要 system_basic 级受限权限（FLOAT_VIEW / USE_FLOAT_BALL），华为 ACL
  //   未批之前 FloatToday.start() 直接返回 NEED_ACL —— 这里只提示、不发起任何
  //   权限申请，避免提审包里出现未获批的权限声明把上架流程卡住。
  private async openFloatToday(): Promise<void> {
    if (FloatToday.isRunning()) {
      promptAction.showToast({ message: $r('app.string.float_toast_running') });
      return;
    }
    const rm = getContext(this).resourceManager;
    // 球面副标题用今天的日柱：短、每天都变，一眼看得出是不是当天的
    let content: string = '';
    const now: Date = new Date();
    const lunar = solar2lunar(now.getFullYear(), now.getMonth() + 1, now.getDate());
    if (lunar) {
      content = rm.getStringSync($r('app.string.float_daygz').id, lunar.gzDay);
    }
    const text: BallText = {
      title: rm.getStringSync($r('app.string.float_today').id),
      content: content
    };
    const ctx = getContext(this) as common.UIAbilityContext;
    const r: FloatStartResult = await FloatToday.start(ctx, text);
    let msg: Resource = $r('app.string.float_toast_failed');
    if (r === FloatStartResult.OK) {
      msg = $r('app.string.float_toast_started');
    } else if (r === FloatStartResult.NEED_ACL) {
      msg = $r('app.string.float_toast_acl');
    } else if (r === FloatStartResult.UNSUPPORTED) {
      msg = $r('app.string.float_toast_unsupported');
    } else if (r === FloatStartResult.PERMISSION_DENIED) {
      msg = $r('app.string.float_toast_denied');
    } else if (r === FloatStartResult.ALREADY_RUNNING) {
      msg = $r('app.string.float_toast_running');
    }
    promptAction.showToast({ message: msg, duration: 2600 });
  }

  private buildParams(): BirthParams {
    return {
      calendarType: this.calendarType,
      gender: this.gender,
      solarYear: this.calendarType === 'solar' ? this.year : 0,
      solarMonth: this.calendarType === 'solar' ? this.month : 0,
      solarDay: this.calendarType === 'solar' ? this.day : 0,
      lunarYear: this.calendarType === 'lunar' ? this.year : 0,
      lunarMonth: this.calendarType === 'lunar' ? this.month : 0,
      lunarDay: this.calendarType === 'lunar' ? this.day : 0,
      isLeap: this.isLeap,
      hour: this.hour,
      minute: this.minute
    };
  }

  // 数字范围（年份覆盖引擎支持的 1900-2100，原先写死 1920-2010
  // 导致 2011 年后出生的人无法排盘，与引擎能力/回归清单都不符）
  private fieldRange(): number[] {
    const a: number[] = [];
    if (this.editField === 'year') {
      for (let y = 1900; y <= 2100; y++) { a.push(y); }
    } else if (this.editField === 'month') {
      for (let m = 1; m <= 12; m++) { a.push(m); }
    } else if (this.editField === 'day') {
      for (let d = 1; d <= 31; d++) { a.push(d); }
    } else if (this.editField === 'minute') {
      for (let m = 0; m <= 59; m++) { a.push(m); }
    } else {
      for (let h = 0; h <= 23; h++) { a.push(h); }
    }
    return a;
  }

  private fieldValue(): number {
    if (this.editField === 'year') { return this.year; }
    if (this.editField === 'month') { return this.month; }
    if (this.editField === 'day') { return this.day; }
    if (this.editField === 'minute') { return this.minute; }
    if (this.editField === 'hour') { return this.hour; }
    return 0;
  }

  private applyField(v: number): void {
    if (this.editField === 'year') { this.year = v; }
    else if (this.editField === 'month') { this.month = v; }
    else if (this.editField === 'day') { this.day = v; }
    else if (this.editField === 'minute') { this.minute = v; }
    else if (this.editField === 'hour') { this.hour = v; }
    this.refreshTip();
  }

  private fieldTitle(): Resource {
    if (this.editField === 'year') {
      return this.calendarType === 'solar' ? $r('app.string.pick_solar_year') : $r('app.string.pick_lunar_year');
    }
    if (this.editField === 'month') {
      return this.calendarType === 'solar' ? $r('app.string.pick_solar_month') : $r('app.string.pick_lunar_month');
    }
    if (this.editField === 'day') {
      return this.calendarType === 'solar' ? $r('app.string.pick_solar_day') : $r('app.string.pick_lunar_day');
    }
    if (this.editField === 'minute') { return $r('app.string.pick_minute'); }
    return $r('app.string.pick_hour');
  }

  build() {
    // 根容器必须是 Stack：生辰编辑弹层要盖在主内容之上，Column 只能纵向排列无法实现浮层
    // 外层 Row 居中 + maxWidth 适配平板/2in1，手机端不受影响。
    Row() {
      Stack() {
      // 主内容区域
      Column() {
        // 品牌头：顶栏 + 中间内容
        // 顶栏：右上角「今日运势」（闪控球/闪控窗）+ 设置
        Row({ space: 8 }) {
          Blank()
          Button($r('app.string.float_today'))
            .fontSize(12)
            .fontColor(COLORS.textSecondary)
            .backgroundColor(COLORS.surface)
            .borderRadius(17)
            .height(34)
            .padding({ left: 12, right: 12 })
            .border({ width: 1, color: COLORS.borderLight })
            .onClick(() => { this.openFloatToday(); })
          Button($r('app.string.settings'))
            .fontSize(12)
            .fontColor(COLORS.textSecondary)
            .backgroundColor(COLORS.surface)
            .borderRadius(17)
            .height(34)
            .padding({ left: 12, right: 12 })
            .border({ width: 1, color: COLORS.borderLight })
            .onClick(() => { router.pushUrl({ url: 'pages/SettingsPage' }); })
        }
        .width('100%')
        .padding({ top: 12, right: 16 })

        // 中间品牌内容
        Column() {
          // 品牌徽标：直接用启动图标（透明底朱砂圆 + 描金「紫」），跟启动窗口同款。
          // 原 Circle+Text+shadow 的方案 shadow 会渲染成矩形外框（黄总 2026-09-02 反馈）。
          Image($r('app.media.startIcon'))
            .width(84)
            .height(84)
            .objectFit(ImageFit.Contain)
            .interpolation(ImageInterpolation.High)

          Text($r('app.string.app_name'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(6)
            .fontColor(COLORS.text)
            .margin({ top: 10 })
          Text($r('app.string.slogan'))
            .fontSize(11)
            .fontColor(COLORS.textMuted)
            .letterSpacing(3)
            .margin({ top: 4 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 20, bottom: 8 })

        Scroll() {
          Column() {
            // ===== 表单卡 =====
            Column() {
              // 行1：历法
              Row() {
                Text($r('app.string.calendar_type')).fontSize(15).fontColor(COLORS.textSecondary).width(64)
                Row() {
                  Text($r('app.string.solar_calendar'))
                    .fontSize(13)
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .borderRadius(7)
                    .backgroundColor(this.calendarType === 'solar' ? COLORS.surface : COLORS.surfaceAlt)
                    .fontColor(this.calendarType === 'solar' ? COLORS.primary : COLORS.textSecondary)
                    .fontWeight(this.calendarType === 'solar' ? FontWeight.Bold : FontWeight.Normal)
                    .onClick(() => {
                      this.calendarType = 'solar';
                      this.refreshTip();
                    })
                  Text($r('app.string.lunar_calendar'))
                    .fontSize(13)
                    .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                    .borderRadius(7)
                    .backgroundColor(this.calendarType === 'lunar' ? COLORS.surface : COLORS.surfaceAlt)
                    .fontColor(this.calendarType === 'lunar' ? COLORS.primary : COLORS.textSecondary)
                    .fontWeight(this.calendarType === 'lunar' ? FontWeight.Bold : FontWeight.Normal)
                    .onClick(() => {
                      this.calendarType = 'lunar';
                      this.refreshTip();
                    })
                }
                .backgroundColor(COLORS.surfaceAlt)
                .borderRadius(9)
                .padding(3)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })

              Divider().strokeWidth(0.5).color(COLORS.borderLight)

              // 行2：生辰（点数字弹轮盘）
              Row() {
                Text($r('app.string.birth_date')).fontSize(15).fontColor(COLORS.textSecondary).width(64)
                Blank()
                Row({ space: 2 }) {
                  Text(this.year.toString())
                    .fontSize(20).fontWeight(FontWeight.Medium)
                    .fontColor(COLORS.text)
                    .height(44)
                    .onClick(() => { this.editField = 'year'; })
                  Text($r('app.string.year')).fontSize(12).fontColor(COLORS.textMuted)
                  Text(this.month.toString())
                    .fontSize(20).fontWeight(FontWeight.Medium)
                    .fontColor(COLORS.text)
                    .padding({ left: 6 })
                    .height(44)
                    .onClick(() => { this.editField = 'month'; })
                  Text($r('app.string.month')).fontSize(12).fontColor(COLORS.textMuted)
                  Text(this.day.toString())
                    .fontSize(20).fontWeight(FontWeight.Medium)
                    .fontColor(COLORS.text)
                    .padding({ left: 6 })
                    .height(44)
                    .onClick(() => { this.editField = 'day'; })
                  Text($r('app.string.day')).fontSize(12).fontColor(COLORS.textMuted)
                  Text(this.hour.toString())
                    .fontSize(20).fontWeight(FontWeight.Medium)
                    .fontColor(COLORS.text)
                    .padding({ left: 10 })
                    .height(44)
                    .onClick(() => { this.editField = 'hour'; })
                  Text($r('app.string.hour')).fontSize(12).fontColor(COLORS.textMuted)
                  Text(this.minute.toString())
                    .fontSize(20).fontWeight(FontWeight.Medium)
                    .fontColor(COLORS.text)
                    .padding({ left: 10 })
                    .height(44)
                    .onClick(() => { this.editField = 'minute'; })
                  Text($r('app.string.minute')).fontSize(12).fontColor(COLORS.textMuted)
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 11, bottom: 4 })

              // 换算提示 + 闰月（农历）
              // 原先公历/农历是两个结构不同的分支：农历分支多一个带边框的「闰」chip，
              // 行高比公历分支高出约 7px，切换历法时下方所有内容整体抽动一下。
              // 合并成单分支 + Hidden 占位，行高恒定。
              Row() {
                Blank()
                Row({ space: 8 }) {
                  Text(this.tipText())
                    .fontSize(11)
                    .fontColor(this.convertFail ? COLORS.error : COLORS.accent)
                  Text($r('app.string.leap'))
                    .fontSize(11)
                    .fontColor(this.isLeap ? COLORS.primary : COLORS.textMuted)
                    .border({ width: 1, color: this.isLeap ? COLORS.primary : COLORS.borderLight })
                    .borderRadius(9)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .visibility(this.calendarType === 'lunar' ? Visibility.Visible : Visibility.Hidden)
                    .onClick(() => {
                      if (this.calendarType !== 'lunar') {
                        return;
                      }
                      this.isLeap = !this.isLeap;
                      this.refreshTip();
                    })
                }
                .padding({ right: 4 })
              }
              .width('100%')
              .padding({ bottom: 10 })

              Divider().strokeWidth(0.5).color(COLORS.borderLight)

              // 行3：性别
              Row() {
                Text($r('app.string.gender_label')).fontSize(15).fontColor(COLORS.textSecondary).width(64)
                Row() {
                  Text($r('app.string.male'))
                    .fontSize(13)
                    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                    .borderRadius(7)
                    .backgroundColor(this.gender === '男' ? COLORS.surface : COLORS.surfaceAlt)
                    .fontColor(this.gender === '男' ? COLORS.primary : COLORS.textSecondary)
                    .fontWeight(this.gender === '男' ? FontWeight.Bold : FontWeight.Normal)
                    .onClick(() => { this.gender = '男'; })
                  Text($r('app.string.female'))
                    .fontSize(13)
                    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                    .borderRadius(7)
                    .backgroundColor(this.gender === '女' ? COLORS.surface : COLORS.surfaceAlt)
                    .fontColor(this.gender === '女' ? COLORS.primary : COLORS.textSecondary)
                    .fontWeight(this.gender === '女' ? FontWeight.Bold : FontWeight.Normal)
                    .onClick(() => { this.gender = '女'; })
                }
                .backgroundColor(COLORS.surfaceAlt)
                .borderRadius(9)
                .padding(3)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 13, bottom: 13 })

              Divider().strokeWidth(0.5).color(COLORS.borderLight)

              // 行4：真太阳时。原先只在设置页，但它改的是「这个人的时辰怎么算」，
              // 属于生辰本身的一部分，放在排盘表单里比埋在设置里更好找。
              Row() {
                Column() {
                  Text($r('app.string.true_solar')).fontSize(15).fontColor(COLORS.textSecondary)
                  Text($r('app.string.true_solar_sub'))
                    .fontSize(11.5)
                    .fontColor(COLORS.textMuted)
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.opts.useTrueSolarTime })
                  .selectedColor(COLORS.primary)
                  .onChange((v: boolean) => {
                    this.setOpt((o: ChartOptions) => { o.useTrueSolarTime = v; });
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })

              Divider().strokeWidth(0.5).color(COLORS.borderLight)

              // 行5：出生地（真太阳时按这里的经度修正）
              Row() {
                Column() {
                  Text($r('app.string.birth_city')).fontSize(15).fontColor(COLORS.textSecondary)
                  Text(this.geoText())
                    .fontSize(11.5)
                    .fontColor(COLORS.textMuted)
                    .margin({ top: 3 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.cityText())
                  .fontSize(13.5)
                  .fontColor(this.city.length > 0 ? COLORS.primary : COLORS.textMuted)
                Text('›').fontSize(17).fontColor(COLORS.textMuted).margin({ left: 6 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .onClick(() => {
                this.cityKeyword = '';
                this.showCity = true;
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 8, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 16 })

            // ===== 排盘按钮 =====
            // 日期非法（公历超范围 / 农历闰月不存在）时置灰：原先仍可点，
            // 点进去必然落到「排盘失败」页，属于界面与功能不一致。
            Button($r('app.string.generate_chart'))
              .width('70%')
              .height(50)
              .fontSize(17)
              .fontColor(COLORS.goldInk)
              .backgroundColor(COLORS.primary)
              .borderRadius(25)
              .shadow({ radius: 14, color: COLORS.primaryGlow, offsetX: 0, offsetY: 4 })
              .margin({ top: 22, bottom: 8 })
              .enabled(!this.convertFail)
              .opacity(this.convertFail ? 0.45 : 1)
              .onClick(() => { this.goChart(this.buildParams()); })

            // ===== 最近排盘 =====
            if (this.recents.length > 0) {
              Column() {
                Row() {
                  Text($r('app.string.recent_charts')).fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLORS.primary)
                  Blank()
                  Text($r('app.string.clear_recent'))
                    .fontSize(12)
                    .fontColor(COLORS.textMuted)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .borderRadius(10)
                    .border({ width: 1, color: COLORS.borderLight })
                    .onClick(() => {
                      AlertDialog.show({
                        title: $r('app.string.recent_charts'),
                        message: $r('app.string.clear_confirm'),
                        confirm: {
                          value: $r('app.string.confirm'),
                          action: () => {
                            this.recents = [];
                            this.saveRecentsClear();
                          }
                        }
                      });
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14 })

                ForEach(this.recents, (it: RecentItem, idx: number) => {
                  Column() {
                    Row() {
                      Column() {
                        Text(this.recentDate(it)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(COLORS.text)
                        Text(it.gender === '男' ? $r('app.string.male') : $r('app.string.female'))
                          .fontSize(11).fontColor(COLORS.textMuted).margin({ top: 2 })
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Text('›').fontSize(20).fontColor(COLORS.textMuted)
                    }
                    .width('100%')
                    .padding({ left: 16, right: 16, top: 11, bottom: 11 })
                    .onClick(() => {
                      const p: BirthParams = {
                        calendarType: it.calendarType,
                        gender: it.gender,
                        solarYear: it.solarYear,
                        solarMonth: it.solarMonth,
                        solarDay: it.solarDay,
                        lunarYear: it.lunarYear,
                        lunarMonth: it.lunarMonth,
                        lunarDay: it.lunarDay,
                        isLeap: it.isLeap,
                        hour: it.hour,
                        minute: it.minute
                      };
                      this.goChart(p);
                    })
                    if (idx < this.recents.length - 1) {
                      Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
                    }
                  }
                  // key 不能带 idx：新记录是插在数组头部的，idx 会整体位移，
                  // 于是全部 key 失效、整个列表销毁重建。label 本身已含
                  // 日期+时辰+性别，且 saveRecent 已按 label 去重，天然唯一。
                }, (it: RecentItem) => it.label)
              }
              .width('100%')
              .borderRadius(16)
              .backgroundColor(COLORS.surface)
              .shadow({ radius: 8, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
              .margin({ left: 16, right: 16, top: 16 })
            }

            // ===== 页脚 =====
            Text($r('app.string.offline_note'))
              .fontSize(11)
              .fontColor(COLORS.textMuted)
              .letterSpacing(2)
              .margin({ top: 18, bottom: 24 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.bg)

      // ===== 生辰编辑弹层 =====
      if (this.editField !== 'none') {
        Column() {
          Blank()
          Column() {
            Row() {
              Text(this.fieldTitle()).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLORS.text)
              Blank()
              Text($r('app.string.close'))
                .fontSize(14).fontColor(COLORS.textMuted)
                .onClick(() => { this.editField = 'none'; })
            }
            .width('100%')
            .margin({ bottom: 8 })

            TextPicker({ range: this.pickerRange(), selected: this.pickerIndex() })
              .backgroundColor(COLORS.bg)
              .onChange((value: string | string[], index: number | number[]) => {
                const i: number = (typeof index === 'number') ? index : 0;
                const arr = this.fieldRange();
                if (i >= 0 && i < arr.length) {
                  this.applyField(arr[i]);
                }
              })
              .layoutWeight(1)

            Button($r('app.string.confirm'))
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor(Color.White)
              .backgroundColor(COLORS.primary)
              .borderRadius(22)
              .margin({ top: 12 })
              .onClick(() => { this.editField = 'none'; })
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
        .onClick(() => { this.editField = 'none'; })
      }

      // ===== 出生地选择浮层（原在设置页，随「基础」组一起搬到首页） =====
      if (this.showCity) {
        Column() {
          Blank()
          Column() {
            Row() {
              Text($r('app.string.select_city')).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLORS.text)
              Blank()
              Text($r('app.string.close'))
                .fontSize(14).fontColor(COLORS.textMuted)
                .onClick(() => { this.showCity = false; })
            }
            .width('100%')
            .margin({ bottom: 10 })

            TextInput({ placeholder: $r('app.string.city_search_hint') })
              .fontSize(14)
              .backgroundColor(COLORS.surfaceAlt)
              .borderRadius(10)
              .height(40)
              .onChange((v: string) => {
                this.cityKeyword = v;
              })

            Scroll() {
              Column() {
                ForEach(this.filteredCities(), (ci: GeoCity) => {
                  Row() {
                    Text(hant(ci.cn))
                      .fontSize(15)
                      .fontColor(ci.cn === this.city ? COLORS.primary : COLORS.text)
                      .layoutWeight(1)
                    Text(ci.lon.toFixed(2) + '°E')
                      .fontSize(12)
                      .fontColor(COLORS.textMuted)
                  }
                  .width('100%')
                  .padding({ left: 6, right: 6, top: 11, bottom: 11 })
                  .borderRadius(8)
                  .backgroundColor(ci.cn === this.city ? COLORS.primarySoft : COLORS.surfaceAlt)
                  .onClick(() => {
                    this.city = ci.cn;
                    this.longitude = ci.lon;
                    this.persistGeo();
                    this.showCity = false;
                  })
                }, (ci: GeoCity) => ci.cn + this.cityKeyword)
                if (this.filteredCities().length === 0) {
                  Text($r('app.string.city_empty'))
                    .fontSize(13)
                    .fontColor(COLORS.textMuted)
                    .padding({ left: 6, top: 14, bottom: 14 })
                }
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(16)
          .height('62%')
          .backgroundColor(COLORS.surface)
          .borderRadius({ topLeft: 20, topRight: 20 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.scrim)
        .onClick(() => { this.showCity = false; })
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

  // 弹层轮盘字符串化（保证 TextPicker 的 range 引用稳定）
  private pickerRange(): string[] {
    if (this.pickerRangeField === this.editField && this.pickerRangeCache.length > 0) {
      return this.pickerRangeCache;
    }
    const out: string[] = [];
    for (const n of this.fieldRange()) {
      out.push(n.toString());
    }
    this.pickerRangeField = this.editField;
    this.pickerRangeCache = out;
    return out;
  }

  private pickerIndex(): number {
    const arr = this.fieldRange();
    const idx = arr.indexOf(this.fieldValue());
    return idx >= 0 ? idx : 0;
  }
}
