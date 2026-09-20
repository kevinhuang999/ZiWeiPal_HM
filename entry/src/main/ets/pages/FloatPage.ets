// 闪控窗页面：今日流日运势。
// 由 floatview/FloatToday.ets 通过 setUIContext('pages/FloatPage') 加载，
// 不在主窗口路由里出现（但必须在 main_pages.json 登记，否则加载失败）。
//
// 取数走「最近排盘」：首页每次排盘都会把生辰写进 preferences('ziwei_recent')，
// 这里读第一条即「我」。不依赖 LocalStorage 传参，避免悬浮窗与主窗两条
// UI 实例之间的状态同步问题。
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { router } from '@kit.ArkUI';
import { loadOptions, loadGeo, GeoInfo } from '../engine/OptionsStore';
import { ChartOptions } from '../engine/ZiWeiEngine';
import { ChartInputs } from '../engine/BuildHelper';
import { computeDailyFortune, DailyFortune, SiHuaItem } from '../engine/DailyFortune';
import { COLORS } from '../engine/Constants';
import { hant } from '../engine/TextConv';
import { FloatToday, FloatShape } from '../floatview/FloatToday';

const RECENT_STORE = 'ziwei_recent';

// 四化类型 → 徽章色（与盘面同一套配色）
function sihuaColor(t: string): string {
  if (t === '禄') { return COLORS.red; }
  if (t === '权') { return COLORS.blue; }
  if (t === '科') { return COLORS.green; }
  return COLORS.purple;
}

@Entry
@Component
struct FloatPage {
  @State fortune: DailyFortune | null = null;
  @State hint: ResourceStr = '';
  @State shape: FloatShape = FloatShape.NORMAL;

  aboutToAppear(): void {
    this.shape = FloatToday.currentShape();
    this.load();
  }

  // 读最近一次排盘 → 按当前口径算今日流日
  private load(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(ctx, RECENT_STORE).then((pf: preferences.Preferences) => {
      const raw = pf.getSync('items', '[]') as string;
      let first: ChartInputs | null = null;
      try {
        const arr = JSON.parse(raw) as ChartInputs[];
        if (arr.length > 0) {
          first = arr[0];
        }
      } catch (e) {
        first = null;
      }
      if (!first) {
        this.hint = $r('app.string.float_toast_norecent');
        return;
      }
      const input: ChartInputs = first;
      return loadOptions(ctx).then((o: ChartOptions) => {
        return loadGeo(ctx).then((g: GeoInfo) => {
          const ii: ChartInputs = input;
          ii.options = o;
          ii.longitude = o.useTrueSolarTime ? g.longitude : null;
          this.fortune = computeDailyFortune(ii, o, new Date());
          if (!this.fortune) {
            this.hint = $r('app.string.float_toast_norecent');
          }
        });
      });
    }).catch(() => {
      this.hint = $r('app.string.float_toast_norecent');
    });
  }

  // 常规态 / mini 态互切
  private toggleShape(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    const next: FloatShape = this.shape === FloatShape.NORMAL ? FloatShape.MINI : FloatShape.NORMAL;
    FloatToday.switchShape(next, ctx).then((ok: boolean) => {
      if (ok) {
        this.shape = next;
      }
    });
  }

  @Builder
  rowOf(label: Resource, value: string, accent: boolean) {
    Row() {
      Text(label).fontSize(10).fontColor(COLORS.textMuted).width(52)
      Text(value)
        .fontSize(12)
        .fontWeight(accent ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(accent ? COLORS.primary : COLORS.text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 3, bottom: 3 })
  }

  build() {
    Column() {
      // 头部：今日 + 公历 / 农历
      Row() {
        Text($r('app.string.float_title')).fontSize(12).fontWeight(FontWeight.Bold).fontColor(COLORS.primary)
        Blank()
        Text($r('app.string.float_shape_normal'))
          .fontSize(9)
          .fontColor(COLORS.textMuted)
          .border({ width: 1, color: COLORS.borderLight })
          .borderRadius(7)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .visibility(this.shape === FloatShape.NORMAL ? Visibility.Visible : Visibility.Hidden)
        Text($r('app.string.float_shape_mini'))
          .fontSize(9)
          .fontColor(COLORS.textMuted)
          .border({ width: 1, color: COLORS.borderLight })
          .borderRadius(7)
          .padding({ left: 6, right: 6, top: 1, bottom: 1 })
          .visibility(this.shape === FloatShape.MINI ? Visibility.Visible : Visibility.Hidden)
      }
      .width('100%')

      if (this.fortune) {
        Text(hant(this.fortune.solarText + '　' + this.fortune.lunarText))
          .fontSize(10)
          .fontColor(COLORS.textSecondary)
          .margin({ top: 2 })
        Text(getContext(this).resourceManager.getStringSync($r('app.string.float_daygz').id,
          this.fortune.dayGanZhi))
          .fontSize(10)
          .fontColor(COLORS.accent)

        Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ top: 6, bottom: 4 })

        this.rowOf($r('app.string.float_liuyue'),
          hant(this.fortune.liuYuePalace + ' · ' + this.fortune.liuYueBranch), true)
        this.rowOf($r('app.string.float_liuri'),
          hant(this.fortune.liuRiPalace + ' · ' + this.fortune.liuRiBranch), true)
        if (this.fortune.liuRiMainStars.length > 0) {
          this.rowOf($r('app.string.float_stars'), hant(this.fortune.liuRiMainStars), false)
        }

        Divider().strokeWidth(0.5).color(COLORS.borderLight).margin({ top: 4, bottom: 4 })

        // 流日四化：2×2
        Grid() {
          ForEach(this.fortune.siHua, (it: SiHuaItem) => {
            GridItem() {
              Row({ space: 4 }) {
                Text(hant(it.type)).fontSize(11).fontWeight(FontWeight.Bold).fontColor(sihuaColor(it.type))
                Text(hant(it.star)).fontSize(11).fontColor(COLORS.textSecondary)
              }
              .padding({ top: 3, bottom: 3 })
            }
          }, (it: SiHuaItem) => it.type)
        }
        .columnsTemplate('1fr 1fr')
        .width('100%')
        .height(48)
      } else {
        Text(this.hint)
          .fontSize(11)
          .fontColor(COLORS.textMuted)
          .margin({ top: 12 })
      }

      Blank()

      // 底部：形态切换 + 回主窗口
      Row({ space: 8 }) {
        Button(this.shape === FloatShape.NORMAL
          ? $r('app.string.float_shape_mini') : $r('app.string.float_shape_normal'))
          .fontSize(11)
          .fontColor(COLORS.primary)
          .backgroundColor(COLORS.primarySoft)
          .borderRadius(13)
          .height(26)
          .layoutWeight(1)
          .onClick(() => {
            this.toggleShape();
          })
        Button($r('app.string.float_back'))
          .fontSize(11)
          .fontColor(COLORS.goldInk)
          .backgroundColor(COLORS.primary)
          .borderRadius(13)
          .height(26)
          .layoutWeight(1)
          .onClick(() => {
            // 悬浮窗里不能用 router：那是悬浮窗自己的路由栈，会把这个小窗导航走。
            // 正确动作是让主窗口回到前台（restoreMainWindow 仅在窗口被点过之后可用，
            // 按钮点击本身就满足这个前提）。
            FloatToday.restoreMain();
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor(COLORS.bg)
  }
}
