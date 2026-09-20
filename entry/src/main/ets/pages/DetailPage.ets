import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ChartResult, StarInfo, ChartOptions, DEFAULT_OPTIONS, cloneOptions } from '../engine/ZiWeiEngine';
import { buildFromInputs, ChartInputs as Inputs, sanFangSiZheng } from '../engine/BuildHelper';
import { loadOptions, loadGeo, GeoInfo } from '../engine/OptionsStore';
import { DI_ZHI_CANG_GAN, MAIN_STAR_NAMES, COLORS } from '../engine/Constants';
import { hant } from '../engine/TextConv';
import { STAR_ATTRIBUTE, StarAttr } from '../engine/AnXingTables';

function sihuaBadgeColor(s: string): string {
  if (s === '禄') { return COLORS.red; }
  if (s === '权') { return COLORS.blue; }
  if (s === '科') { return COLORS.green; }
  return COLORS.purple;
}

function starAttr(name: string): StarAttr | null {
  const i = MAIN_STAR_NAMES.indexOf(name);
  return i >= 0 ? STAR_ATTRIBUTE[i] : null;
}

@Entry
@Component
struct DetailPage {
  @State chart: ChartResult | null = null;
  @State inputs: Inputs | null = null;
  @State palaceIndex: number = 0;
  @State infoText: ResourceStr = '';
  // 排盘口径必须与命盘页一致：原先不传 options，详情页用 DEFAULT_OPTIONS 重算，
  // 用户一改四化流派/换年换月/闰月处理/真太阳时等，两个页面的同一条信息就会打架。
  private opts: ChartOptions = cloneOptions(DEFAULT_OPTIONS);
  private longitude: number | null = null;
  private currentAge: number = 0;

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
    // 宫序必须落在 0-11，否则 c.palaces[NaN] 会抛错导致白屏
    const pi: number = Number(params['palaceIndex'] ?? 0);
    this.palaceIndex = (!isNaN(pi) && pi >= 0 && pi <= 11) ? Math.floor(pi) : 0;
    // 命盘页当前年龄：小限要按它推算，原先没传，导致「小限」永远显示 —
    this.currentAge = Number(params['currentAge'] ?? 0);
    const ctx = getContext(this) as common.UIAbilityContext;
    loadOptions(ctx).then((o: ChartOptions) => {
      this.opts = o;
      return loadGeo(ctx);
    }).then((g: GeoInfo) => {
      this.longitude = this.opts.useTrueSolarTime ? g.longitude : null;
      this.rebuild();
    }).catch(() => {
      this.infoText = $r('app.string.err_settings');
    });
  }

  rebuild(): void {
    const i = this.inputs;
    if (!i) {
      return;
    }
    const merged: ChartOptions = cloneOptions(this.opts);
    merged.currentAge = this.currentAge > 0 ? this.currentAge : null;
    const c = buildFromInputs({
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
      options: merged,
      longitude: this.longitude
    });
    if (c) {
      this.chart = c;
    } else {
      this.infoText = $r('app.string.err_date_range');
    }
  }

  // 组合文案（@Builder 内不能声明局部变量，统一放普通方法）
  private fmt1(key: Resource, a: string): string {
    return getContext(this).resourceManager.getStringSync(key.id, a);
  }

  private cangGan(c: ChartResult): string {
    return (DI_ZHI_CANG_GAN[c.palaces[this.palaceIndex].dizhi] || []).join('、');
  }

  private palaceSuffixText(c: ChartResult): string {
    return hant(this.fmt1($r('app.string.palace_suffix'), c.palaces[this.palaceIndex].dizhi));
  }

  private heroGanzhiText(c: ChartResult): string {
    return hant(getContext(this).resourceManager.getStringSync($r('app.string.hero_ganzhi').id,
      c.palaces[this.palaceIndex].ganzhi, this.cangGan(c)));
  }

  private kvGanzhiText(c: ChartResult): string {
    return hant(getContext(this).resourceManager.getStringSync($r('app.string.palace_cang').id,
      c.palaces[this.palaceIndex].ganzhi, this.cangGan(c)));
  }

  private daXianChipText(c: ChartResult): string {
    return getContext(this).resourceManager.getStringSync($r('app.string.chip_daxian').id,
      `${c.palaces[this.palaceIndex].daXianStart}`, `${c.palaces[this.palaceIndex].daXianEnd}`);
  }

  private ageRangeText(c: ChartResult): string {
    return getContext(this).resourceManager.getStringSync($r('app.string.age_range').id,
      `${c.palaces[this.palaceIndex].daXianStart}`, `${c.palaces[this.palaceIndex].daXianEnd}`);
  }

  private ageValueText(c: ChartResult): string {
    return this.fmt1($r('app.string.age_val'), `${c.palaces[this.palaceIndex].xiaoXianAge}`);
  }

  private twelveText(c: ChartResult): string {
    return hant(getContext(this).resourceManager.getStringSync($r('app.string.twelve_val').id,
      c.palaces[this.palaceIndex].changSheng,
      c.palaces[this.palaceIndex].boShi,
      c.palaces[this.palaceIndex].jiangQian));
  }

  private sfLine(c: ChartResult): string {
    return this.fmt1($r('app.string.sf_names'), this.sfNamesText(c));
  }

  // 星曜属性文本（空串表示无属性）
  private starAttrText(name: string): string {
    const attr = starAttr(name);
    if (attr) {
      return hant(getContext(this).resourceManager.getStringSync($r('app.string.star_attr_val').id,
        attr.wx, attr.yy, attr.hq));
    }
    return '';
  }

  // 三方四正宫名文本
  private sfNamesText(c: ChartResult): string {
    const sf = sanFangSiZheng(this.palaceIndex);
    let out = '';
    for (let i = 0; i < sf.length; i++) {
      if (i > 0) {
        out += '、';
      }
      out += c.palaces[sf[i]].palaceName + '（' + c.palaces[sf[i]].dizhi + '）';
    }
    return hant(out);
  }

  @Builder
  errorView() {
    Column() {
      Text(this.infoText).fontSize(16).fontColor(COLORS.error).margin(24)
      Button($r('app.string.back')).onClick(() => router.back())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.bg)
    .justifyContent(FlexAlign.Center)
  }

  // 卡片头（短竖条 + 标题）
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

  // 主星行
  @Builder
  mainStarRow(s: StarInfo) {
    Column({ space: 3 }) {
      Row({ space: 6 }) {
        Text(hant(s.name)).fontSize(18).fontWeight(FontWeight.Medium).fontColor(COLORS.text)
        if (s.brightness) {
          Text(hant(s.brightness)).fontSize(12).fontColor(COLORS.textMuted)
        }
        if (s.sihua) {
          Text(hant(s.sihua))
            .fontSize(10)
            .fontColor(Color.White)
            .backgroundColor(sihuaBadgeColor(s.sihua))
            .borderRadius(4)
            .padding({ left: 4, right: 4 })
        }
      }
      if (this.starAttrText(s.name).length > 0) {
        Text(this.starAttrText(s.name))
          .fontSize(11.5)
          .fontColor(COLORS.textSecondary)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  // 键值行
  @Builder
  kvRow(k: ResourceStr, v: ResourceStr) {
    Row() {
      Text(k).fontSize(12.5).fontColor(COLORS.textMuted).width(84)
      Text(v).fontSize(13.5).fontColor(COLORS.text).layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  detailView(c: ChartResult) {
    Column() {
      // 顶栏
      Row() {
        Text('‹')
          .fontSize(22)
          .fontColor(COLORS.textSecondary)
          .width(38)
          .height(38)
          .textAlign(TextAlign.Center)
          .borderRadius(19)
          .backgroundColor(COLORS.surface)
          .border({ width: 1, color: COLORS.borderLight })
          .onClick(() => router.back())
        Text(hant(c.palaces[this.palaceIndex].palaceName))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .letterSpacing(2)
          .margin({ left: 8 })
        Blank()
        Text(this.palaceSuffixText(c))
          .fontSize(13)
          .fontColor(COLORS.accent)
          .margin({ right: 16 })
      }
      .width('100%')
      .height(52)
      .padding({ left: 12 })

      Scroll() {
        Column() {
          // ===== 宫位 Hero =====
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              if (this.palaceIndex === c.mingGongIndex) {
                Text($r('app.string.ming_gong'))
                  .fontSize(11).fontColor(Color.White)
                  .backgroundColor(COLORS.primary)
                  .borderRadius(11)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              }
              if (this.palaceIndex === c.shenGongIndex) {
                Text($r('app.string.shen_gong'))
                  .fontSize(11).fontColor(Color.White)
                  .backgroundColor(COLORS.green)
                  .borderRadius(11)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              }
              if (c.palaces[this.palaceIndex].daXianStart >= 0) {
                Text(this.daXianChipText(c))
                  .fontSize(11).fontColor(COLORS.primary)
                  .backgroundColor(COLORS.primarySoft)
                  .borderRadius(11)
                  .padding({ left: 10, right: 10, top: 3, bottom: 3 })
              }
              Text($r('app.string.san_fang'))
                .fontSize(11).fontColor(COLORS.blue)
                .backgroundColor(COLORS.blueSoft)
                .borderRadius(11)
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            }
            .width('100%')

            if (c.palaces[this.palaceIndex].mainStars.length > 0) {
              Text(hant(c.palaces[this.palaceIndex].mainStars.map((s: StarInfo) =>
                s.name + (s.brightness ? ` ${s.brightness}` : '')).join(' · ')))
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.text)
                .letterSpacing(1)
            } else {
              Text($r('app.string.empty_gong'))
                .fontSize(25)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.textMuted)
                .letterSpacing(4)
            }

            Text(this.heroGanzhiText(c))
              .fontSize(12)
              .fontColor(COLORS.accent)

            Text(this.sfLine(c))
              .fontSize(11.5)
              .fontColor(COLORS.blue)
              .maxLines(2)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 18, right: 18, top: 18, bottom: 16 })
          .borderRadius(18)
          .backgroundColor(COLORS.heroBg)
          .border({ width: 1, color: COLORS.border })
          .margin({ left: 16, right: 16, top: 6 })

          // ===== 主星卡 =====
          Column() {
            this.cardHead($r('app.string.main_stars'), COLORS.primary)
            if (c.palaces[this.palaceIndex].mainStars.length === 0) {
              Text($r('app.string.empty_palace_hint'))
                .fontSize(13).fontColor(COLORS.textMuted)
                .padding({ left: 16, top: 10, bottom: 14 })
            } else {
              ForEach(c.palaces[this.palaceIndex].mainStars, (s: StarInfo) => {
                this.mainStarRow(s)
              }, (s: StarInfo) => s.name)
            }
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor(COLORS.surface)
          .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
          .margin({ left: 16, right: 16, top: 14 })

          // ===== 辅星卡 =====
          if (c.palaces[this.palaceIndex].auxStars.length > 0) {
            Column() {
              this.cardHead($r('app.string.aux_stars'), COLORS.green)
              Text(hant(c.palaces[this.palaceIndex].auxStars.map((s: StarInfo) =>
                s.name + (s.sihua ? s.sihua : '')).join('　')))
                .fontSize(15)
                .fontColor(COLORS.text)
                .lineHeight(26)
                .padding({ left: 16, right: 16, top: 10, bottom: 14 })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 14 })
          }

          // ===== 宫位信息卡 =====
          Column() {
            this.cardHead($r('app.string.palace_info'), COLORS.textSecondary)
            Column() {
              this.kvRow($r('app.string.palace_stem'), this.kvGanzhiText(c))
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              this.kvRow($r('app.string.da_xian'),
                c.palaces[this.palaceIndex].daXianStart >= 0 ? this.ageRangeText(c) : $r('app.string.dash'))
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              this.kvRow($r('app.string.xiao_xian'),
                c.palaces[this.palaceIndex].xiaoXianAge >= 0 ? this.ageValueText(c) : $r('app.string.dash'))
              Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              if (c.palaces[this.palaceIndex].changSheng) {
                this.kvRow($r('app.string.twelve_gods'), this.twelveText(c))
                Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ left: 16, right: 16 })
              }
              this.kvRow($r('app.string.san_fang'), this.sfNamesText(c))
            }
            .padding({ bottom: 8 })
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor(COLORS.surface)
          .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
          .margin({ left: 16, right: 16, top: 14 })

          // ===== 神煞卡 =====
          if (c.palaces[this.palaceIndex].shenSha.length > 0) {
            Column() {
              this.cardHead($r('app.string.shen_sha'), COLORS.textSecondary)
              Text(hant(c.palaces[this.palaceIndex].shenSha.join('　')))
                .fontSize(14)
                .fontColor(COLORS.text)
                .lineHeight(24)
                .padding({ left: 16, right: 16, top: 10, bottom: 14 })
            }
            .width('100%')
            .borderRadius(16)
            .backgroundColor(COLORS.surface)
            .shadow({ radius: 6, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
            .margin({ left: 16, right: 16, top: 14 })
          }

          Blank().height(24)
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
  }

  build() {
    // 外层 Row 居中 + maxWidth 适配平板/2in1，手机端不受影响。
    Row() {
      Column() {
      if (this.chart) {
        this.detailView(this.chart)
      } else {
        this.errorView()
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
