// 紫微排盘常量与基础工具（对齐 PC 版 ZiWei.Core）
// 地支编号：子0 丑1 寅2 卯3 辰4 巳5 午6 未7 申8 酉9 戌10 亥11
// 天干编号：甲0 乙1 丙2 丁3 戊4 己5 庚6 辛7 壬8 癸9
// 所有模 12 取非负余数：((x % 12) + 12) % 12

// 十天干
export const TIAN_GAN: string[] = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];

// 十二地支
export const DI_ZHI: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];

// 地支藏干（用于详情页显示）
export const DI_ZHI_CANG_GAN: Record<string, string[]> = {
  '子': ['癸'],
  '丑': ['己', '癸', '辛'],
  '寅': ['甲', '丙', '戊'],
  '卯': ['乙'],
  '辰': ['戊', '乙', '癸'],
  '巳': ['丙', '庚', '戊'],
  '午': ['丁', '己'],
  '未': ['己', '丁', '乙'],
  '申': ['庚', '壬', '戊'],
  '酉': ['辛'],
  '戌': ['戊', '辛', '丁'],
  '亥': ['壬', '甲']
};

// 十二宫名（逆时针序，数组下标即序：命、兄、夫、子、财、疾、迁、友、官、田、福、父）
export const PALACE_NAMES: string[] = [
  '命宫', '兄弟', '夫妻', '子女', '财帛', '疾厄',
  '迁移', '仆役', '官禄', '田宅', '福德', '父母'
];

// 十四主星名（序号固定，与 PC StarName 一致：0=紫微…13=破军）
export const MAIN_STAR_NAMES: string[] = [
  '紫微', '天机', '太阳', '武曲', '天同', '廉贞', '天府',
  '太阴', '贪狼', '巨门', '天相', '天梁', '七杀', '破军'
];

// 辅星名（14 颗）
export const AUX_STAR_NAMES: string[] = [
  '左辅', '右弼', '文昌', '文曲', '天空', '地劫', '天魁', '天钺',
  '禄存', '擎羊', '陀罗', '火星', '铃星', '天马'
];

// 四化类型
export const SI_HUA_TYPES: string[] = ['禄', '权', '科', '忌'];

// 亮度七级
export const BRIGHTNESS_NAMES: string[] = ['庙', '旺', '得', '利', '平', '不', '陷'];

// 五行局名（下标 = ju-2）
export const WU_XING_JU_NAMES: string[] = ['水二局', '木三局', '金四局', '土五局', '火六局'];

// 十二神顺序
export const CHANG_SHENG_ORDER: string[] = ['长生', '沐浴', '冠带', '临官', '帝旺', '衰', '病', '死', '墓', '绝', '胎', '养'];
export const BO_SHI_ORDER: string[] = ['博士', '力士', '青龙', '小耗', '将军', '奏书', '飞廉', '喜神', '病符', '大耗', '伏兵', '官府'];
export const JIANG_QIAN_ORDER: string[] = ['将星', '攀鞍', '岁驿', '息神', '华盖', '劫煞', '灾煞', '天煞', '指背', '咸池', '月煞', '亡神'];
// 岁前十二星：由生年支起「岁建」顺行（文墨天机同口径）
export const SUI_QIAN_ORDER: string[] = ['岁建', '晦气', '丧门', '贯索', '官符', '小耗', '岁破', '龙德', '白虎', '天德', '吊客', '病符'];

// 地支序号查询
export function zhiIndex(zhi: string): number {
  return DI_ZHI.indexOf(zhi);
}

// 天干序号查询
export function ganIndex(gan: string): number {
  return TIAN_GAN.indexOf(gan);
}

// 天干阴阳
export function ganYinYang(gan: string): '阳' | '阴' {
  const i = TIAN_GAN.indexOf(gan);
  return i >= 0 && i % 2 === 0 ? '阳' : '阴';
}

// 地支阴阳
export function zhiYinYang(zhi: string): '阳' | '阴' {
  const i = DI_ZHI.indexOf(zhi);
  return i >= 0 && i % 2 === 0 ? '阳' : '阴';
}

// 天干五行
export function ganWuXing(gan: string): string {
  const map: Record<string, string> = {
    '甲': '木', '乙': '木', '丙': '火', '丁': '火', '戊': '土', '己': '土',
    '庚': '金', '辛': '金', '壬': '水', '癸': '水'
  };
  return map[gan] ?? '?';
}

// 地支五行
export function zhiWuXing(zhi: string): string {
  const map: Record<string, string> = {
    '子': '水', '丑': '土', '寅': '木', '卯': '木', '辰': '土', '巳': '火',
    '午': '火', '未': '土', '申': '金', '酉': '金', '戌': '土', '亥': '水'
  };
  return map[zhi] ?? '?';
}

// 时辰地支索引（hour 0-23；23 点起算子时）
export function hourBranchIndex(hour: number): number {
  if (hour >= 23 || hour < 1) return 0; // 子
  if (hour < 3) return 1; // 丑
  if (hour < 5) return 2; // 寅
  if (hour < 7) return 3; // 卯
  if (hour < 9) return 4; // 辰
  if (hour < 11) return 5; // 巳
  if (hour < 13) return 6; // 午
  if (hour < 15) return 7; // 未
  if (hour < 17) return 8; // 申
  if (hour < 19) return 9; // 酉
  if (hour < 21) return 10; // 戌
  return 11; // 亥
}

export function hourName(hour: number): string {
  // 必须与引擎同一个 hourBranchFromHour：真太阳时可算出 >=24 的小时（跨日），
  // 而 hourBranchIndex 对 >=24 一律返回子时，会造成「首页显示子时、命盘按丑时起盘」
  return DI_ZHI[hourBranchFromHour(hour)] + '时';
}

// 时辰地支（含跨日，真太阳时用）
export function hourBranchFromHour(hour: number): number {
  return ((Math.floor((hour + 1) / 2)) % 12 + 12) % 12;
}

// 模 12 非负
export function mod12(x: number): number {
  return ((x % 12) + 12) % 12;
}

// 配色（古纸朱砂 · 低饱和国风，参考文墨天机/问真等专业排盘观感）
// 全部页面统一引用，改色只动这里
export interface Palette {
  primary: string;
  primaryDark: string;
  primarySoft: string;
  bg: string;
  surface: string;
  surfaceAlt: string;
  text: string;
  textSecondary: string;
  textMuted: string;
  border: string;
  borderLight: string;
  accent: string;
  blue: string;
  blueSoft: string;
  green: string;
  greenSoft: string;
  red: string;
  purple: string;
  purpleSoft: string;
  goldInk: string;
  centerBg: string;
  toastBg: string;
  primaryGlow: string;
  primaryGlowSoft: string;
  error: string;
  heroBg: string;
  shadowSoft: string;
  scrim: string;
}

export const COLORS: Palette = {
  primary: '#9B2E23',      // 朱砂（传统矿物色，主按钮/选中/四化禄）
  primaryDark: '#6E2118',  // 深朱砂（按下态）
  primarySoft: '#F2E2DA',  // 浅朱砂（命宫底色，低饱和）
  bg: '#F8F4EC',           // 古绢米白（页面底色）
  surface: '#FFFFFF',      // 纯白（卡面）
  surfaceAlt: '#F5EFE2',   // 米褐（次级卡面）
  text: '#33302B',         // 墨（主文字）
  textSecondary: '#6B5D4F',// 茶褐（副标题）
  textMuted: '#6E6556',    // 灰褐（次要文字/亮度）— 对比度提升至 5.74:1（白底），满足 WCAG AA
  border: '#D8CFC0',       // 浅茶褐（边框）
  borderLight: '#E8E1D4',  // 极淡茶褐（宫格线）
  accent: '#8A6408',       // 金棕（宫干/强调）— 对比度提升至 5.37:1（白底）
  blue: '#425066',         // 黛蓝（三方四正/流年）
  blueSoft: '#E4E8F0',     // 浅黛蓝（选中宫底色）
  green: '#5F7D52',        // 竹青（辅星/身宫）
  greenSoft: '#E8EFE3',    // 浅竹青（四化科徽章/横条底）
  red: '#9B2E23',          // 朱砂（四化禄，同主色）
  purple: '#8C4356',       // 绛紫（四化忌）
  purpleSoft: '#F3E3E8',   // 浅绛紫（四化忌徽章/横条底）
  goldInk: '#F8E9C8',      // 描金（朱砂上的金字/中宫描边）
  centerBg: '#FBF8F0',     // 中宫底（比页面底稍暖）
  toastBg: '#EB33302B',    // Toast 底（墨 90%）
  primaryGlow: '#529B2E23',    // 主按钮发光（朱砂 32%）——修正原 #52199999 笔误
  primaryGlowSoft: '#249B2E23',// 选中宫格柔光（朱砂 14%）
  error: '#C0392B',         // 错误红
  heroBg: '#FDFAF3',        // 详情页 Hero 卡底（暖白）
  shadowSoft: '#0F000000',  // 卡片通用投影（黑 6%）
  scrim: '#66000000'        // 弹层遮罩（黑 40%）
};
