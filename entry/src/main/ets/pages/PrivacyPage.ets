import { router } from '@kit.ArkUI';
import { COLORS } from '../engine/Constants';

// 隐私政策页：华为上架强制要求应用内提供隐私政策入口。
// 本应用数据面极干净（不采集 / 不申请权限 / 不联网 / 仅本机存储），政策很短。
// 所有文案均走资源键，避免界面硬编码中文。
@Entry
@Component
struct PrivacyPage {
  build() {
    Row() {
      Column() {
        // 顶栏
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
          Text($r('app.string.privacy_title'))
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .letterSpacing(2)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(52)
        .padding({ left: 12 })

        Scroll() {
          Column({ space: 14 }) {
            Text($r('app.string.privacy_subtitle'))
              .fontSize(13)
              .fontColor(COLORS.textSecondary)
              .width('100%')

            this.policyCard($r('app.string.privacy_collect_title'), $r('app.string.privacy_collect_body'))
            this.policyCard($r('app.string.privacy_permission_title'), $r('app.string.privacy_permission_body'))
            this.policyCard($r('app.string.privacy_network_title'), $r('app.string.privacy_network_body'))

            // 工信部 App 备案号（占位，待黄总填写）
            Row() {
              Text($r('app.string.privacy_filing'))
                .fontSize(12)
                .fontColor(COLORS.textMuted)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .borderRadius(16)
            .backgroundColor(COLORS.surfaceAlt)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
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

  // 单条政策卡片（标题 + 正文）
  @Builder
  policyCard(title: Resource, body: Resource) {
    Column({ space: 6 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.primary)
      Text(body)
        .fontSize(13)
        .fontColor(COLORS.textSecondary)
        .lineHeight(20)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .borderRadius(16)
    .backgroundColor(COLORS.surface)
    .shadow({ radius: 8, color: COLORS.shadowSoft, offsetX: 0, offsetY: 2 })
    .alignItems(HorizontalAlign.Start)
  }
}
