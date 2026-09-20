import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';
import { DEFAULT_OPTIONS, ChartOptions, cloneOptions,
  YearStyle, MonthStyle, SiHuaStyle, LeapMonthStyle, DaXianStartStyle, XiaoXianStyle } from '../engine/ZiWeiEngine';
import { loadOptions, saveOptions } from '../engine/OptionsStore';
import { COLORS } from '../engine/Constants';

// 枚举选项项（ArkTS 不支持对象字面量类型，须显式声明 interface）
interface OptionItem {
  key: string;
  name: Resource;
}

// 值选择浮层定义（ArkTS 须显式 interface）
interface PickerSheet {
  field: string; // 'siHuaStyle'|'yearStyle'|'monthStyle'|'leapMonthStyle'|'daXianStartStyle'|'xiaoXianStyle'|'lang'
  title: Resource;
  options: OptionItem[];
}

// 开关行。
// 为什么是独立 @Component 而不是 @Builder：@Builder 的参数按值传递，
// 参数源是状态变量时，状态变化不会触发 @Builder 内的 UI 刷新（ArkUI 明确约束）。
// 原来的写法让「真太阳时」等开关首帧渲染成默认值后再也不动 —— 这就是
// 「设置改了、退出再进又变回默认」的根因。子组件用 @Prop 才能跟着刷新。
@Component
struct OptionSwitchRow {
  label: Resource = $r('app.string.dash');
  sub: Resource = $r('app.string.dash');
  @Prop on: boolean = false;
  onToggle: (v: boolean) => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.label).fontSize(15).fontColor(COLORS.text)
        Text(this.sub).fontSize(11.5).fontColor(COLORS.textMuted).margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.on })
        .selectedColor(COLORS.primary)
        .onChange((v: boolean) => {
          this.onToggle(v);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }
}

// 取值行（点开浮层）。value 走 @Prop 传字符串，同上避免参数不刷新。
@Component
struct OptionValueRow {
  label: Resource = $r('app.string.dash');
  sub: Resource = $r('app.string.dash');
  @Prop value: string = '';
  onPick: () => void = () => {};

  build() {
    Row() {
      Column() {
        Text(this.label).fontSize(15).fontColor(COLORS.text)
        Text(this.sub).fontSize(11.5).fontColor(COLORS.textMuted).margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.value)
        .fontSize(13.5)
        .fontColor(COLORS.primary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 170 })

      Text('›').fontSize(17).fontColor(COLORS.textMuted).margin({ left: 6 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => {
      this.onPick();
    })
  }
}

@Entry
@Component
struct SettingsPage {
  @State opts: ChartOptions = DEFAULT_OPTIONS;
  @State sheet: PickerSheet | null = null;
  // 语言档位：'follow' 跟随系统 | 'hans' 简体 | 'hant' 繁体。
  // 只用来渲染「当前选中项」，不是偏好的存储 —— 真正的偏好由系统托管（见 applyLang）。
  @State langKey: string = 'follow';

  aboutToAppear(): void {
    this.langKey = this.detectLang();
    const ctx = getContext(this) as common.UIAbilityContext;
    loadOptions(ctx).then((o: ChartOptions) => {
      this.opts = o;
    }).catch(() => {
    });
  }

  private persist(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    saveOptions(ctx, this.opts).catch(() => {
    });
  }

  // ── 语言：读 / 写 / 判定 ────────────────────────────────────────────
  // 偏好语言由系统持久化（i18n.System.setAppPreferredLanguage），本应用不再存
  // 第二份，免得两处状态打架。「跟随系统」用 'default' 表达，由系统清除偏好。

  private detectLang(): string {
    let p: string = '';
    try {
      p = i18n.System.getAppPreferredLanguage();
    } catch (e) {
      return 'follow';
    }
    if (p.indexOf('Hant') >= 0 || p.indexOf('TW') >= 0
      || p.indexOf('HK') >= 0 || p.indexOf('MO') >= 0) {
      return 'hant';
    }
    if (p.indexOf('Hans') >= 0 || p.indexOf('-CN') >= 0) {
      return 'hans';
    }
    return 'follow';
  }

  // 只改本应用的语言，不动系统设置。
  // 切完直接改 langKey（@State）——本页会重渲染，资源引用与 getStringSync
  // 都会按新语言重新取值，不必重启应用。
  private applyLang(key: string): void {
    try {
      if (key === 'hant') {
        i18n.System.setAppPreferredLanguage('zh-Hant');
      } else if (key === 'hans') {
        i18n.System.setAppPreferredLanguage('zh-Hans');
      } else {
        i18n.System.setAppPreferredLanguage('default');
      }
    } catch (e) {
    }
    this.langKey = key;
  }

  private langOptions(): OptionItem[] {
    return [
      { key: 'follow', name: $r('app.string.lang_follow') },
      { key: 'hans', name: $r('app.string.lang_hans') },
      { key: 'hant', name: $r('app.string.lang_hant') }
    ];
  }

  private langLabel(): string {
    const rm = getContext(this).resourceManager;
    for (const it of this.langOptions()) {
      if (it.key === this.langKey) {
        return rm.getStringSync(it.name.id);
      }
    }
    return rm.getStringSync($r('app.string.lang_follow').id);
  }

  // 改选项：整个对象替换（不原地改字段），确保 @State 一定触发重渲染
  private setOpt(apply: (o: ChartOptions) => void): void {
    const next: ChartOptions = cloneOptions(this.opts);
    apply(next);
    this.opts = next;
    this.persist();
  }

  // 当前值显示文本。取成 string 再交给子组件的 @Prop（@Prop 对简单类型最稳）
  private optLabel(items: OptionItem[], key: string): string {
    const rm = getContext(this).resourceManager;
    for (const it of items) {
      if (it.key === key) {
        return rm.getStringSync(it.name.id);
      }
    }
    return rm.getStringSync($r('app.string.dash').id);
  }

  private siHuaOptions(): OptionItem[] {
    return [
      { key: 'NanPai', name: $r('app.string.nan_pai') },
      { key: 'ZhongZhou', name: $r('app.string.zhong_zhou') }
    ];
  }

  private yearOptions(): OptionItem[] {
    return [
      { key: 'LunarYear', name: $r('app.string.year_lunar') },
      { key: 'LiChun', name: $r('app.string.li_chun') }
    ];
  }

  private monthOptions(): OptionItem[] {
    return [
      { key: 'LunarMonth', name: $r('app.string.month_lunar') },
      { key: 'SolarTerm', name: $r('app.string.solar_term_month') }
    ];
  }

  private leapOptions(): OptionItem[] {
    return [
      { key: 'HalfMonth', name: $r('app.string.half_month') },
      { key: 'WholePrev', name: $r('app.string.whole_prev') },
      { key: 'WholeNext', name: $r('app.string.whole_next') }
    ];
  }

  private daXianOptions(): OptionItem[] {
    return [
      { key: 'Ju', name: $r('app.string.by_ju') },
      { key: 'AgeOne', name: $r('app.string.age_one') }
    ];
  }

  private xiaoXianOptions(): OptionItem[] {
    return [
      { key: 'MingPalace', name: $r('app.string.from_ming') },
      { key: 'YearBranch', name: $r('app.string.from_year_branch') }
    ];
  }

  // 选择浮层应用
  private applySheet(key: string): void {
    const s = this.sheet;
    if (!s) {
      return;
    }
    const field: string = s.field;
    // 语言不是 ChartOptions 里的字段，走自己的写入路径
    if (field === 'lang') {
      this.applyLang(key);
      this.sheet = null;
      return;
    }
    this.setOpt((o: ChartOptions) => {
      if (field === 'siHuaStyle') { o.siHuaStyle = key as SiHuaStyle; }
      else if (field === 'yearStyle') { o.yearStyle = key as YearStyle; }
      else if (field === 'monthStyle') { o.monthStyle = key as MonthStyle; }
      else if (field === 'leapMonthStyle') { o.leapMonthStyle = key as LeapMonthStyle; }
      else if (field === 'daXianStartStyle') { o.daXianStartStyle = key as DaXianStartStyle; }
      else if (field === 'xiaoXianStyle') { o.xiaoXianStyle = key as XiaoXianStyle; }
    });
    this.sheet = null;
  }

  // 浮层当前选中判断
  private isSheetSelected(key: string): boolean {
    const s = this.sheet;
    if (!s) {
      return false;
    }
    if (s.field === 'lang') { return this.langKey === key; }
    if (s.field === 'siHuaStyle') { return this.opts.siHuaStyle === key; }
    if (s.field === 'yearStyle') { return this.opts.yearStyle === key; }
    if (s.field === 'monthStyle') { return this.opts.monthStyle === key; }
    if (s.field === 'leapMonthStyle') { return this.opts.leapMonthStyle === key; }
    if (s.field === 'daXianStartStyle') { return this.opts.daXianStartStyle === key; }
    if (s.field === 'xiaoXianStyle') { return this.opts.xiaoXianStyle === key; }
    return false;
  }

  // 卡片头
  @Builder
  cardHead(label: Resource, color: string) {
    Row({ space: 7 }) {
      Text('')
        .width(4)
        .height(13)
        .borderRadius(2)
        .backgroundColor(color)
      Text(label).fontSize(13).fontWeight(FontWeight.Bold).fontColor(color)
    }
    .padding({ left: 16, top: 14 })
  }

  // 浮层选项行
  @Builder
  sheetOption(item: OptionItem, selected: boolean) {
    Row() {
      Text(item.name)
        .fontSize(14.5)
        .fontColor(selected ? COLORS.primary : COLORS.text)
        .layoutWeight(1)
      if (selected) {
        Text('✓').fontSize(15).fontColor(COLORS.primary)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 13, bottom: 13 })
    .onClick(() => {
      this.applySheet(item.key);
    })
  }

  build() {
    // 外层 Row 居中 + maxWidth 适配平板/2in1，手机端不受影响。
    Row() {
      Stack() {
        Column() {
        // 顶栏
        Row() {
        Text('‹')
          .fontSize(22)
          .fontColor(COLORS.textSecondary)
          .width(44)
          .height(44)
            .textAlign(TextAlign.Center)
            .borderRadius(19)
            .backgroundColor(COLORS.surface)
            .border({ width: 1, color: COLORS.borderLight })
            .onClick(() => router.back())
          Text($r('app.string.settings'))
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(2)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(52)
        .padding({ left: 12 })

        Scroll() {
          Column() {
            // ===== 组1：外观 =====
            // 放在最前：语言是用户最先要找的设置项（旧版本没有语言切换入口，
            // 只能跟随系统，用户翻遍设置页也找不到）。
            Column() {
              this.cardHead($r('app.string.appearance_group'), COLORS.primary)
              OptionValueRow({
                label: $r('app.string.ui_language'),
                sub: $r('app.string.ui_language_sub'),
                value: this.langLabel(),
                onPick: () => {
                  this.sheet = { field: 'lang', title: $r('app.string.ui_language'), options: this.langOptions() };
                }
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 14 })
            .alignItems(HorizontalAlign.Start)

            // ===== 组2：排盘口径 =====
            // 「真太阳时 + 出生地」原是本页的第一组，已搬到首页排盘表单的「性别」
            // 下方 —— 它们改的是「这个人的时辰怎么算」，属于生辰本身，放在排盘
            // 表单里比埋在设置页更好找，也免得同一项两处可改。
            Column() {
              this.cardHead($r('app.string.rules_group'), COLORS.primary)
              OptionValueRow({
                label: $r('app.string.sihua_school'),
                sub: $r('app.string.sihua_school_sub'),
                value: this.optLabel(this.siHuaOptions(), this.opts.siHuaStyle),
                onPick: () => {
                  this.sheet = { field: 'siHuaStyle', title: $r('app.string.sihua_school'), options: this.siHuaOptions() };
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionValueRow({
                label: $r('app.string.year_style'),
                sub: $r('app.string.year_style_sub'),
                value: this.optLabel(this.yearOptions(), this.opts.yearStyle),
                onPick: () => {
                  this.sheet = { field: 'yearStyle', title: $r('app.string.year_style'), options: this.yearOptions() };
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionValueRow({
                label: $r('app.string.month_style'),
                sub: $r('app.string.month_style_sub'),
                value: this.optLabel(this.monthOptions(), this.opts.monthStyle),
                onPick: () => {
                  this.sheet = { field: 'monthStyle', title: $r('app.string.month_style'), options: this.monthOptions() };
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionSwitchRow({
                label: $r('app.string.late_zi'),
                sub: $r('app.string.late_zi_sub'),
                on: this.opts.lateZiSwitchDay,
                onToggle: (v: boolean) => {
                  this.setOpt((o: ChartOptions) => { o.lateZiSwitchDay = v; });
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionValueRow({
                label: $r('app.string.leap_month'),
                sub: $r('app.string.leap_month_sub'),
                value: this.optLabel(this.leapOptions(), this.opts.leapMonthStyle),
                onPick: () => {
                  this.sheet = { field: 'leapMonthStyle', title: $r('app.string.leap_month'), options: this.leapOptions() };
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionValueRow({
                label: $r('app.string.da_xian_start'),
                sub: $r('app.string.da_xian_start_sub'),
                value: this.optLabel(this.daXianOptions(), this.opts.daXianStartStyle),
                onPick: () => {
                  this.sheet = { field: 'daXianStartStyle', title: $r('app.string.da_xian_start'), options: this.daXianOptions() };
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionValueRow({
                label: $r('app.string.xiao_xian_opt'),
                sub: $r('app.string.xiao_xian_opt_sub'),
                value: this.optLabel(this.xiaoXianOptions(), this.opts.xiaoXianStyle),
                onPick: () => {
                  this.sheet = { field: 'xiaoXianStyle', title: $r('app.string.xiao_xian_opt'), options: this.xiaoXianOptions() };
                }
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 14 })
            .alignItems(HorizontalAlign.Start)

            // ===== 组3：显示开关 =====
            Column() {
              this.cardHead($r('app.string.display_group'), COLORS.primary)
              OptionSwitchRow({
                label: $r('app.string.show_shen_sha'),
                sub: $r('app.string.show_shen_sha_sub'),
                on: this.opts.showShenSha,
                onToggle: (v: boolean) => {
                  this.setOpt((o: ChartOptions) => { o.showShenSha = v; });
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionSwitchRow({
                label: $r('app.string.show_extra'),
                sub: $r('app.string.show_extra_sub'),
                on: this.opts.showExtraShenSha,
                onToggle: (v: boolean) => {
                  this.setOpt((o: ChartOptions) => { o.showExtraShenSha = v; });
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionSwitchRow({
                label: $r('app.string.show_brightness'),
                sub: $r('app.string.show_brightness_sub'),
                on: this.opts.showBrightness,
                onToggle: (v: boolean) => {
                  this.setOpt((o: ChartOptions) => { o.showBrightness = v; });
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionSwitchRow({
                label: $r('app.string.show_twelve'),
                sub: $r('app.string.show_twelve_sub'),
                on: this.opts.showTwelveShen,
                onToggle: (v: boolean) => {
                  this.setOpt((o: ChartOptions) => { o.showTwelveShen = v; });
                }
              })
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              OptionSwitchRow({
                label: $r('app.string.show_liunian'),
                sub: $r('app.string.show_liunian_sub'),
                on: this.opts.showLiuNianFull,
                onToggle: (v: boolean) => {
                  this.setOpt((o: ChartOptions) => { o.showLiuNianFull = v; });
                }
              })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 14 })
            .alignItems(HorizontalAlign.Start)

            // ===== 关于 =====
            Column() {
              this.cardHead($r('app.string.about_group'), COLORS.textSecondary)
              Row() {
                Text($r('app.string.version_label')).fontSize(12.5).fontColor(COLORS.textMuted).width(84)
                Text($r('app.string.version_value')).fontSize(13.5).fontColor(COLORS.text)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              Row() {
                Text($r('app.string.verify_label')).fontSize(12.5).fontColor(COLORS.textMuted).width(84)
                Text($r('app.string.verify_value')).fontSize(13.5).fontColor(COLORS.text)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 14 })
              Row() {
                Text($r('app.string.privacy_title')).fontSize(13.5).fontColor(COLORS.text)
                Blank()
                Text('›').fontSize(17).fontColor(COLORS.textMuted)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 14 })
              .onClick(() => { router.pushUrl({ url: 'pages/PrivacyPage' }); })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 14, bottom: 24 })
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.bg)

      // ===== 值选择浮层 =====
      if (this.sheet !== null) {
        Column() {
          Blank()
          Column() {
            Row() {
              Text(this.sheet.title)
                .fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLORS.text)
              Blank()
              Text($r('app.string.close'))
                .fontSize(14).fontColor(COLORS.textMuted)
                .onClick(() => { this.sheet = null; })
            }
            .width('100%')
            .margin({ bottom: 6 })

            Scroll() {
              Column() {
                ForEach(this.sheet.options, (item: OptionItem) => {
                  this.sheetOption(item, this.isSheetSelected(item.key))
                }, (item: OptionItem) => item.key)
              }
              .width('100%')
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
          }
          .width('100%')
          .padding(16)
          .height('46%')
          .backgroundColor(COLORS.surface)
          .borderRadius({ topLeft: 20, topRight: 20 })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(COLORS.scrim)
        .onClick(() => { this.sheet = null; })
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
}
