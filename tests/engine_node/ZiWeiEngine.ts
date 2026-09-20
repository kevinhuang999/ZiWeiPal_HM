// 紫微斗数排盘核心引擎（对齐 PC 版 ZiWei.Core，自研 ArkTS）
// 地支编号：子0…亥11；天干编号：甲0…癸9；模 12 取非负余数
import { solar2lunar, lunar2solar, dayPillarIndex, trueSolarCorrectedHour } from './CalendarUtil.ts';
import { jieMomentJd, jdToLocal } from './SolarTerms.ts';
import { TIAN_GAN, DI_ZHI, PALACE_NAMES, MAIN_STAR_NAMES, WU_XING_JU_NAMES,
  BRIGHTNESS_NAMES, CHANG_SHENG_ORDER, BO_SHI_ORDER, JIANG_QIAN_ORDER, SUI_QIAN_ORDER, hourBranchFromHour, mod12 } from './Constants.ts';
import {
  ZI_WEI_BY_DAY, TIAN_FU_BY_ZI_WEI, ZI_WEI_CLUSTER, TIAN_FU_CLUSTER,
  LU_CUN_BY_STEM, KUI_YUE_BY_STEM, TIAN_MA_BY_BRANCH, HUO_XING_START, LING_XING_START,
  SI_HUA_NAN_PAI, SI_HUA_ZHONG_ZHOU, stemNumber, branchNumber, juFromNaYin, daXianStartAge,
  XIAO_XIAN_START_BY_BRANCH, MING_ZHU_BY_BRANCH, SHEN_ZHU_BY_BRANCH, BRIGHTNESS_TABLE,
  sanHeGroup, yearSiJu, XIAN_CHI, HUA_GAI, JIANG_XING, GU_CHEN, GUA_SU,
  TIAN_DE, YUE_DE, TIAN_YUE, TIAN_WU_BY_MONTH, TIAN_GUAN_BY_STEM, TIAN_FU_GUI_BY_STEM
} from './AnXingTables.ts';

// 流派选项的字面量联合类型（ArkTS 不支持索引访问类型，须具名导出）
export type YearStyle = 'LunarYear' | 'LiChun';
export type MonthStyle = 'LunarMonth' | 'SolarTerm';
export type SiHuaStyle = 'NanPai' | 'ZhongZhou';
export type LeapMonthStyle = 'HalfMonth' | 'WholePrev' | 'WholeNext';
export type DaXianStartStyle = 'Ju' | 'AgeOne';
export type XiaoXianStyle = 'MingPalace' | 'YearBranch';

export interface ChartOptions {
  lateZiSwitchDay: boolean;
  yearStyle: YearStyle;
  monthStyle: MonthStyle;
  siHuaStyle: SiHuaStyle;
  useTrueSolarTime: boolean;
  leapMonthStyle: LeapMonthStyle;
  daXianStartStyle: DaXianStartStyle;
  xiaoXianStyle: XiaoXianStyle;
  showShenSha: boolean;
  showExtraShenSha: boolean;
  showBrightness: boolean;
  showTwelveShen: boolean;
  showLiuNianFull: boolean;
  liuNianYear: number | null;
  currentAge: number | null;
}

export const DEFAULT_OPTIONS: ChartOptions = {
  // 09-12 黄总拍板：晚子时日 / 真太阳时默认开启。
  // 已存过旧设置的手机由 OptionsStore 的 defaultsVer 迁移一次性刷成新默认。
  lateZiSwitchDay: true,
  yearStyle: 'LunarYear',
  monthStyle: 'LunarMonth',
  siHuaStyle: 'NanPai',
  useTrueSolarTime: true,
  leapMonthStyle: 'HalfMonth',
  daXianStartStyle: 'Ju',
  // 09-12 对拍文墨天机：小限默认改「按年支起宫」（通说口径，XIAO_XIAN_START_BY_BRANCH
  // 表已对拍验证：卯年→丑起，文墨样例逐宫吻合）。「从命宫起」保留为可选流派。
  xiaoXianStyle: 'YearBranch',
  showShenSha: true,
  showExtraShenSha: true,
  showBrightness: true,
  showTwelveShen: true,
  showLiuNianFull: true,
  liuNianYear: null,
  currentAge: null
};

// 复制选项（ArkTS 不支持对象展开运算符，逐字段复制；Partial 缺省回落默认值）
export function cloneOptions(src: Partial<ChartOptions>): ChartOptions {
  const o: ChartOptions = {
    lateZiSwitchDay: src.lateZiSwitchDay ?? DEFAULT_OPTIONS.lateZiSwitchDay,
    yearStyle: src.yearStyle ?? DEFAULT_OPTIONS.yearStyle,
    monthStyle: src.monthStyle ?? DEFAULT_OPTIONS.monthStyle,
    siHuaStyle: src.siHuaStyle ?? DEFAULT_OPTIONS.siHuaStyle,
    useTrueSolarTime: src.useTrueSolarTime ?? DEFAULT_OPTIONS.useTrueSolarTime,
    leapMonthStyle: src.leapMonthStyle ?? DEFAULT_OPTIONS.leapMonthStyle,
    daXianStartStyle: src.daXianStartStyle ?? DEFAULT_OPTIONS.daXianStartStyle,
    xiaoXianStyle: src.xiaoXianStyle ?? DEFAULT_OPTIONS.xiaoXianStyle,
    showShenSha: src.showShenSha ?? DEFAULT_OPTIONS.showShenSha,
    showExtraShenSha: src.showExtraShenSha ?? DEFAULT_OPTIONS.showExtraShenSha,
    showBrightness: src.showBrightness ?? DEFAULT_OPTIONS.showBrightness,
    showTwelveShen: src.showTwelveShen ?? DEFAULT_OPTIONS.showTwelveShen,
    showLiuNianFull: src.showLiuNianFull ?? DEFAULT_OPTIONS.showLiuNianFull,
    liuNianYear: src.liuNianYear ?? DEFAULT_OPTIONS.liuNianYear,
    currentAge: src.currentAge ?? DEFAULT_OPTIONS.currentAge
  };
  return o;
}

export interface StarInfo {
  name: string;
  tier: number; // 0 主星 / 2 辅星
  brightness: string; // 庙旺落陷，空=无
  sihua: string; // 生年四化，空=无
  selfSihua: string; // 宫干自化：↓X 离心 / ↑X 向心，多个用 / 分隔，空=无
}

export interface StarCell {
  palaceIndex: number;
  palaceName: string;
  dizhi: string;
  stem: string;
  ganzhi: string;
  mainStars: StarInfo[];
  auxStars: StarInfo[];
  shenSha: string[];
  changSheng: string;
  boShi: string;
  jiangQian: string;
  suiQian: string; // 岁前星（由年支起岁建顺行）
  xiaoXianAges: number[]; // 1-120 虚岁全周期小限落宫年龄
  liuNianAges: number[]; // 1-120 虚岁中流年落本宫的年龄
  dieGongAges: number[]; // 限流叠宫：大限命宫+流年+小限三者同宫的虚岁
  daXianStart: number;
  daXianEnd: number;
  xiaoXianAge: number;
  liuNianName: string;
  liuYue: number; // -1 未排
}

export interface ChartResult {
  solarYear: number; solarMonth: number; solarDay: number;
  lunarYear: number; lunarMonth: number; lunarDay: number; isLeap: boolean; chartMonth: number;
  hour: number; minute: number; gender: string; longitude: number | null; useTrueSolar: boolean;
  yearGanZhi: string; monthGanZhi: string; dayGanZhi: string; hourGanZhi: string;
  jieQiSiZhu: string; feiJieQiSiZhu: string; // 节气口径 / 非节气（农历）口径四柱，导出用
  trueSolarHour: number; // 真太阳时小时数（未启用真太阳时=钟表时），导出用
  laiYinIndex: number; // 来因宫宫序（年干所落宫），-1 无
  yearGan: number; yearBranch: number;
  mingGongIndex: number; shenGongIndex: number; wuXingJu: string; wuXingJuNum: number;
  ziWeiIndex: number; tianFuIndex: number;
  palaces: StarCell[];
  siHua: Record<string, string>;
  mingZhu: string; shenZhu: string;
  liuNianYear: number | null; liuNianMingIndex: number; liuNianSiHua: Record<string, string>;
  douJunIndex: number; daXianMingIndex: number; daXianSiHua: Record<string, string>;
  xiaoXianIndex: number; xiaoXianAge: number;
}

export interface BuildInput {
  solarYear?: number; solarMonth?: number; solarDay?: number;
  lunarYear?: number; lunarMonth?: number; lunarDay?: number; isLeap?: boolean;
  hour: number; minute?: number; gender: string; longitude?: number | null;
  options?: Partial<ChartOptions>;
}

// ===== 四柱工具 =====
function gzYear(year: number): string {
  const g = TIAN_GAN[((year - 4) % 10 + 10) % 10];
  const z = DI_ZHI[((year - 4) % 12 + 12) % 12];
  return g + z;
}
function monthPillarByStem(yearStem: number, chartMonth: number): string {
  const zhengYueStem = (yearStem * 2 + 2) % 10;
  const stem = (zhengYueStem + chartMonth - 1) % 10;
  const branch = (2 + chartMonth - 1) % 12;
  return TIAN_GAN[stem] + DI_ZHI[branch];
}
function hourPillar(dayStem: number, hourBranch: number): string {
  const ziStem = (dayStem % 5) * 2;
  const stem = (ziStem + hourBranch) % 10;
  return TIAN_GAN[stem] + DI_ZHI[hourBranch];
}
function momentToMs(y: number, m: number, d: number, h: number): number {
  const hh = Math.floor(h);
  const mm = Math.round((h - hh) * 60);
  return Date.UTC(y, m - 1, d, hh, mm);
}
function liChunMs(year: number): number {
  const loc = jdToLocal(jieMomentJd(year, 0) + 8 / 24);
  return momentToMs(loc.year, loc.month, loc.day, loc.hour);
}
function jieMs(year: number, k: number): number {
  const loc = jdToLocal(jieMomentJd(year, k) + 8 / 24);
  return momentToMs(loc.year, loc.month, loc.day, loc.hour);
}
function monthPillarBySolarTerm(year: number, yearGan: number, ms: number): string {
  if (ms < liChunMs(year)) {
    const prevStem = (((year - 1 - 4) % 10) + 10) % 10;
    return monthPillarByStem(prevStem, 12);
  }
  let k = 0;
  for (let i = 0; i < 12; i++) {
    if (ms >= jieMs(year, i)) k++;
  }
  return monthPillarByStem(yearGan, k);
}
function computeChartMonth(lm: number, isLeap: boolean, ld: number, style: LeapMonthStyle): number {
  if (!isLeap) return lm;
  if (style === 'WholePrev') return lm;
  if (style === 'WholeNext') return lm + 1;
  return ld <= 15 ? lm : lm + 1; // HalfMonth
}
function dayOfYear(y: number, m: number, d: number): number {
  const past = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  let doy = past[m - 1] + d;
  if (m > 2 && ((y % 4 === 0 && y % 100 !== 0) || y % 400 === 0)) doy += 1;
  return doy;
}

// 首页展示用：按真太阳时口径换算出生时刻（与 buildChart 内部同一套公式，
// 避免首页显示「酉时」而命盘实际按「申时」起盘的界面/功能不一致）
export function trueSolarHourFor(solarY: number, solarM: number, solarD: number,
  hour: number, minute: number, longitude: number): number {
  const stdHour = hour + minute / 60.0;
  return trueSolarCorrectedHour(stdHour, longitude, dayOfYear(solarY, solarM, solarD));
}

// 星曜落宫（地支序 → 宫序）
function placeMain(palaces: StarCell[], mingBranch: number, starBranch: number, name: string): void {
  const pIdx = mod12(starBranch - mingBranch);
  palaces[pIdx].mainStars.push({ name: name, tier: 0, brightness: '', sihua: '', selfSihua: '' });
}
function placeAux(palaces: StarCell[], mingBranch: number, starBranch: number, name: string): void {
  const pIdx = mod12(starBranch - mingBranch);
  palaces[pIdx].auxStars.push({ name: name, tier: 2, brightness: '', sihua: '', selfSihua: '' });
}
function applySiHua(palaces: StarCell[], siHua: Record<string, string>): void {
  for (const p of palaces) {
    for (const s of [...p.mainStars, ...p.auxStars]) {
      if (siHua[s.name]) s.sihua = siHua[s.name];
    }
  }
}
// 十二神放置（start 为地支序，dir=true 顺行）
function placeTwelve(palaces: StarCell[], mingBranch: number, startBranch: number, dir: boolean, order: string[]): void {
  for (let k = 0; k < 12; k++) {
    const br = mod12(startBranch + (dir ? k : -k));
    const pIdx = mod12(br - mingBranch);
    if (order[0] === CHANG_SHENG_ORDER[0]) palaces[pIdx].changSheng = order[k];
    else if (order[0] === BO_SHI_ORDER[0]) palaces[pIdx].boShi = order[k];
    else palaces[pIdx].jiangQian = order[k];
  }
}
function addShenSha(palaces: StarCell[], mingBranch: number, branch: number, name: string): void {
  palaces[mod12(branch - mingBranch)].shenSha.push(name);
}
// 60 甲子序号（甲子=0）：i 满足 i%10==干 且 i%12==支
function ganZhiIndex(gan: number, branch: number): number {
  for (let i = 0; i < 60; i++) {
    if (i % 10 === gan && i % 12 === branch) return i;
  }
  return 0;
}
function computeShenSha(palaces: StarCell[], mingBranch: number, shenBranch: number, yearGan: number, yb: number, chartMonth: number, hb: number, ld: number): void {
  const Fwd = (s: number) => mod12(s + yb);
  const Rev = (s: number) => mod12(s - yb);
  // 红鸾：由卯宫起子，逆数至年支；天喜固定安在红鸾对宫
  addShenSha(palaces, mingBranch, Rev(3), '红鸾');
  addShenSha(palaces, mingBranch, Rev(9), '天喜');
  // 天刑（酉起正月顺至生月）、天姚（丑起正月顺至生月）—— 月系，原误按年支
  addShenSha(palaces, mingBranch, mod12(9 + chartMonth - 1), '天刑');
  addShenSha(palaces, mingBranch, mod12(1 + chartMonth - 1), '天姚');
  // 龙池（辰起子顺至年支）、凤阁（戌起子逆至年支）—— 年系
  addShenSha(palaces, mingBranch, Fwd(4), '龙池');
  addShenSha(palaces, mingBranch, Rev(10), '凤阁');
  // 三台：左辅宫起初一顺至生日；八座：右弼宫起初一逆至生日 —— 日系
  addShenSha(palaces, mingBranch, mod12(4 + chartMonth - 1 + ld - 1), '三台');
  addShenSha(palaces, mingBranch, mod12(11 - chartMonth - (ld - 1)), '八座');
  // 台辅（午起子顺至生时）、封诰（寅起子顺至生时）—— 时系，原误按年支
  addShenSha(palaces, mingBranch, mod12(6 + hb), '台辅');
  addShenSha(palaces, mingBranch, mod12(2 + hb), '封诰');
  addShenSha(palaces, mingBranch, Fwd(6), '天虚');
  addShenSha(palaces, mingBranch, Fwd(5), '天厨');
  // 天官 / 天福贵人 —— 年干系，原误按年支
  addShenSha(palaces, mingBranch, TIAN_GUAN_BY_STEM[yearGan], '天官');
  addShenSha(palaces, mingBranch, TIAN_FU_GUI_BY_STEM[yearGan], '天福');
  // 天巫 —— 月系：正五九月巳、二六十月申、三七十一寅、四八十二亥
  addShenSha(palaces, mingBranch, TIAN_WU_BY_MONTH[(chartMonth - 1) % 4], '天巫');
  // 恩光（文昌宫起初一顺至生日再退一步）、天贵（文曲宫同法）—— 日系
  addShenSha(palaces, mingBranch, mod12(11 - hb + ld - 1 - 1), '恩光');
  addShenSha(palaces, mingBranch, mod12(4 + hb + ld - 1 - 1), '天贵');
  addShenSha(palaces, mingBranch, Rev(6), '天哭');
  const group = sanHeGroup(yb);
  addShenSha(palaces, mingBranch, XIAN_CHI[group], '咸池');
  addShenSha(palaces, mingBranch, HUA_GAI[group], '华盖');
  addShenSha(palaces, mingBranch, JIANG_XING[group], '将星');
  const sj = yearSiJu(yb);
  addShenSha(palaces, mingBranch, GU_CHEN[sj], '孤辰');
  addShenSha(palaces, mingBranch, GUA_SU[sj], '寡宿');
  if (chartMonth >= 1 && chartMonth <= 12) addShenSha(palaces, mingBranch, TIAN_DE[chartMonth - 1], '天德');
  const mb = mod12(2 + chartMonth - 1);
  addShenSha(palaces, mingBranch, YUE_DE[sanHeGroup(mb)], '月德');
}
function computeExtraShenSha(palaces: StarCell[], mingBranch: number, shenBranch: number, yearGan: number, yb: number, chartMonth: number, hb: number): void {
  // 旬空：年干支 60 甲子序号
  const gzIndex = ganZhiIndex(yearGan, yb);
  const xunGroup = Math.floor(gzIndex / 10);
  const xunStart = mod12(10 - 2 * xunGroup);
  addShenSha(palaces, mingBranch, xunStart, '旬空');
  addShenSha(palaces, mingBranch, mod12(xunStart + 1), '旬空');
  // 截空
  const jieGroup = yearGan % 5;
  const jieStart = mod12(8 - 2 * jieGroup);
  addShenSha(palaces, mingBranch, jieStart, '截空');
  addShenSha(palaces, mingBranch, mod12(jieStart + 1), '截空');
  addShenSha(palaces, mingBranch, mod12(jieStart + 6), '截空');
  addShenSha(palaces, mingBranch, mod12(jieStart + 7), '截空');
  // 阴煞
  addShenSha(palaces, mingBranch, mod12(2 - 2 * ((chartMonth - 1) % 6)), '阴煞');
  // 天使 / 天伤
  // 天使在疾厄宫（命宫顺 5）、天伤在交友宫（命宫顺 7）
  addShenSha(palaces, mingBranch, mod12(mingBranch + 5), '天使');
  addShenSha(palaces, mingBranch, mod12(mingBranch + 7), '天伤');
  // 蜚廉
  const feiGroup = Math.floor(yb / 3);
  const feiBase = mod12(8 - 3 * feiGroup);
  addShenSha(palaces, mingBranch, mod12(feiBase + (yb % 3)), '蜚廉');
  // 破碎
  let poSui = 1;
  if (yb % 3 === 0) poSui = 5; else if (yb % 3 === 2) poSui = 9; else poSui = 1;
  addShenSha(palaces, mingBranch, poSui, '破碎');
  // 天才 / 天寿
  addShenSha(palaces, mingBranch, mod12(mingBranch + yb), '天才');
  addShenSha(palaces, mingBranch, mod12(shenBranch + yb), '天寿');
  // 解神
  const jieShenGroup = Math.floor((chartMonth - 1) / 2);
  addShenSha(palaces, mingBranch, mod12(8 + 2 * jieShenGroup), '解神');
  // 天月
  if (chartMonth >= 1 && chartMonth <= 12) addShenSha(palaces, mingBranch, TIAN_YUE[chartMonth - 1], '天月');
}

export function buildChart(input: BuildInput): ChartResult | null {
  const opts: ChartOptions = input.options ? cloneOptions(input.options) : cloneOptions(DEFAULT_OPTIONS);

  // 1. 归一化农历
  let ly: number, lm: number, ld: number, isLeap: boolean;
  if (input.lunarYear && input.lunarYear > 0) {
    ly = input.lunarYear; lm = input.lunarMonth ?? 1; ld = input.lunarDay ?? 1; isLeap = input.isLeap ?? false;
  } else {
    const r = solar2lunar(input.solarYear ?? 0, input.solarMonth ?? 1, input.solarDay ?? 1);
    if (!r) return null;
    ly = r.lYear; lm = r.lMonth; ld = r.lDay; isLeap = r.isLeap;
  }
  // 2. 公历
  let solarY: number, solarM: number, solarD: number;
  if (input.solarYear && input.solarYear > 0) {
    solarY = input.solarYear; solarM = input.solarMonth ?? 1; solarD = input.solarDay ?? 1;
  } else {
    const rs = lunar2solar(ly, lm, ld, isLeap);
    if (!rs) return null;
    solarY = rs.solarYear; solarM = rs.solarMonth; solarD = rs.solarDay;
  }

  const chartMonth = computeChartMonth(lm, isLeap, ld, opts.leapMonthStyle);

  // 4. 时辰（真太阳时）
  const minute = input.minute ?? 0;
  const stdHour = input.hour + minute / 60.0;
  const doy = dayOfYear(solarY, solarM, solarD);
  const useLong = opts.useTrueSolarTime && input.longitude != null;
  let hourOfDay = stdHour;
  if (useLong) hourOfDay = trueSolarCorrectedHour(stdHour, input.longitude as number, doy);
  const nativeBranch = hourBranchFromHour(stdHour);
  const hb = useLong ? hourBranchFromHour(hourOfDay) : nativeBranch;

  // 5. 四柱
  let yearGz: string;
  if (opts.yearStyle === 'LiChun') {
    const ms = momentToMs(solarY, solarM, solarD, stdHour);
    yearGz = ms >= liChunMs(solarY) ? gzYear(solarY) : gzYear(solarY - 1);
  } else {
    yearGz = gzYear(ly);
  }
  const yearGan = TIAN_GAN.indexOf(yearGz.charAt(0));
  const yearBranch = DI_ZHI.indexOf(yearGz.charAt(1));

  let monthGz: string;
  if (opts.monthStyle === 'SolarTerm') {
    const ms = momentToMs(solarY, solarM, solarD, stdHour);
    monthGz = monthPillarBySolarTerm(solarY, yearGan, ms);
  } else {
    monthGz = monthPillarByStem(yearGan, chartMonth);
  }

  let di = dayPillarIndex(solarY, solarM, solarD);
  // 晚子时换日；真太阳时算出 >=24 说明已跨到次日，日柱同样要跟着换
  if ((opts.lateZiSwitchDay && hourOfDay >= 23) || hourOfDay >= 24) {
    di = dayPillarIndex(solarY, solarM, solarD + 1);
  }
  const dayGz = TIAN_GAN[di % 10] + DI_ZHI[di % 12];
  const dayStem = di % 10;
  const hourGz = hourPillar(dayStem, hb);

  // 节气/非节气双四柱（导出用）：节气按立春界+节气月，非节气按农历年+农历月柱
  const birthMs = momentToMs(solarY, solarM, solarD, stdHour);
  const jieQiYearGz = birthMs >= liChunMs(solarY) ? gzYear(solarY) : gzYear(solarY - 1);
  const jieQiMonthGz = monthPillarBySolarTerm(solarY, TIAN_GAN.indexOf(jieQiYearGz.charAt(0)), birthMs);
  const feiJieQiYearGz = gzYear(ly);
  const feiJieQiMonthGz = monthPillarByStem(TIAN_GAN.indexOf(feiJieQiYearGz.charAt(0)), chartMonth);
  const jieQiSiZhu: string = jieQiYearGz + ' ' + jieQiMonthGz + ' ' + dayGz + ' ' + hourGz;
  const feiJieQiSiZhu: string = feiJieQiYearGz + ' ' + feiJieQiMonthGz + ' ' + dayGz + ' ' + hourGz;

  // 6. 命宫/身宫
  const monthPos = mod12(2 + chartMonth - 1);
  const mingBranch = mod12(monthPos - hb);
  const shenBranch = mod12(monthPos + hb);

  // 7. 十二宫
  const palaces: StarCell[] = [];
  for (let i = 0; i < 12; i++) {
    const dizhi = DI_ZHI[mod12(mingBranch + i)];
    // ★十二宫宫名逆布（09-12 对拍文墨天机样例修正）：兄弟宫在命宫地支逆行一位。
    //   本数组下标 i = 地支顺行偏移 mod12(branch - mingBranch)（全引擎星曜/四化/大限/
    //   流年均按此落位，体系自洽），故宫名取 PALACE_NAMES[mod12(12 - i)]，
    //   即兄弟=i11、父母=i1、财帛=i8、官禄=i4。此前误写 PALACE_NAMES[i]（顺布），
    //   导致除命宫/迁移外十宫宫名全部错位。
    palaces.push({
      palaceIndex: i, palaceName: PALACE_NAMES[mod12(12 - i)], dizhi: dizhi,
      stem: '', ganzhi: '', mainStars: [], auxStars: [], shenSha: [],
      changSheng: '', boShi: '', jiangQian: '', suiQian: '',
      xiaoXianAges: [], liuNianAges: [], dieGongAges: [],
      daXianStart: -1, daXianEnd: -1, xiaoXianAge: -1, liuNianName: '', liuYue: -1
    });
  }

  // 8. 十二宫天干
  const yinStem = (yearGan * 2 + 2) % 10;
  for (let i = 0; i < 12; i++) {
    const b = mod12(mingBranch + i);
    const stem = (yinStem + mod12(b - 2)) % 10;
    palaces[i].stem = TIAN_GAN[stem];
    palaces[i].ganzhi = TIAN_GAN[stem] + DI_ZHI[b];
  }

  // 9. 五行局
  const mingStem = TIAN_GAN.indexOf(palaces[0].stem);
  const naYinSum = stemNumber(mingStem) + branchNumber(mingBranch);
  const ju = juFromNaYin(naYinSum);

  // 10-11. 紫微/天府
  const ziWeiBranch = ZI_WEI_BY_DAY[ju - 2][ld - 1];
  const tianFuBranch = TIAN_FU_BY_ZI_WEI[ziWeiBranch];

  // 12. 十四主星
  placeMain(palaces, mingBranch, ziWeiBranch, '紫微');
  for (const c of ZI_WEI_CLUSTER) placeMain(palaces, mingBranch, mod12(ziWeiBranch - c.step), c.name);
  placeMain(palaces, mingBranch, tianFuBranch, '天府');
  for (const c of TIAN_FU_CLUSTER) placeMain(palaces, mingBranch, mod12(tianFuBranch + c.step), c.name);

  // 13. 辅星 14
  placeAux(palaces, mingBranch, mod12(4 + chartMonth - 1), '左辅');
  placeAux(palaces, mingBranch, mod12(11 - chartMonth), '右弼');
  // 「辰上顺时文曲位，戌上逆时觅文昌」（生时）：文曲=辰(4)+时支顺行；文昌=戌(10)-时支逆行
  placeAux(palaces, mingBranch, mod12(4 + hb), '文曲');
  placeAux(palaces, mingBranch, mod12(10 - hb), '文昌');
  // 空劫：亥(11)上起子时，顺安地劫、逆安地空（09-12 对拍文墨修正：原把地空误名天空）
  placeAux(palaces, mingBranch, mod12(11 - hb), '地空');
  placeAux(palaces, mingBranch, mod12(11 + hb), '地劫');
  // 天空：「丑宫起子，数至本生年支」（ncc 安星诀；卯年得辰，与文墨天机对拍吻合）。
  // 文墨把天空列「小星」非辅星（六煞只有羊陀火铃空劫），故入杂曜桶 shenSha。
  addShenSha(palaces, mingBranch, mod12(1 + yearBranch), '天空');
  placeAux(palaces, mingBranch, KUI_YUE_BY_STEM[yearGan][0], '天魁');
  placeAux(palaces, mingBranch, KUI_YUE_BY_STEM[yearGan][1], '天钺');
  const luCun = LU_CUN_BY_STEM[yearGan];
  placeAux(palaces, mingBranch, luCun, '禄存');
  placeAux(palaces, mingBranch, mod12(luCun + 1), '擎羊');
  placeAux(palaces, mingBranch, mod12(luCun - 1), '陀罗');
  placeAux(palaces, mingBranch, mod12(HUO_XING_START[yearBranch] + hb), '火星');
  placeAux(palaces, mingBranch, mod12(LING_XING_START[yearBranch] + hb), '铃星');
  placeAux(palaces, mingBranch, TIAN_MA_BY_BRANCH[yearBranch], '天马');

  // 14. 四化（本命）
  const siHuaTable = opts.siHuaStyle === 'ZhongZhou' ? SI_HUA_ZHONG_ZHOU : SI_HUA_NAN_PAI;
  const row = siHuaTable[yearGan];
  const siHua: Record<string, string> = {};
  siHua[row[0]] = '禄'; siHua[row[1]] = '权'; siHua[row[2]] = '科'; siHua[row[3]] = '忌';
  applySiHua(palaces, siHua);

  // 14b. 岁前十二星：由生年支起「岁建」顺行（文墨天机同口径，导出用）
  for (let k = 0; k < 12; k++) {
    palaces[mod12(mod12(yearBranch + k) - mingBranch)].suiQian = SUI_QIAN_ORDER[k];
  }

  // 14c. 宫干自化：本宫宫干四化入本宫之星=离心↓；化入对宫之星=向心↑（标记落在被化入宫的那颗星上）
  const selfTypes: string[] = ['禄', '权', '科', '忌'];
  for (let i = 0; i < 12; i++) {
    const st = TIAN_GAN.indexOf(palaces[i].stem);
    const srow = siHuaTable[st];
    const opp = palaces[mod12(i + 6)];
    for (let t = 0; t < 4; t++) {
      const star = srow[t];
      for (const s of [...palaces[i].mainStars, ...palaces[i].auxStars]) {
        if (s.name === star) s.selfSihua = s.selfSihua ? s.selfSihua + '/↓' + selfTypes[t] : '↓' + selfTypes[t];
      }
      for (const s of [...opp.mainStars, ...opp.auxStars]) {
        if (s.name === star) s.selfSihua = s.selfSihua ? s.selfSihua + '/↑' + selfTypes[t] : '↑' + selfTypes[t];
      }
    }
  }

  // 15. 大限
  const yang = yearGan % 2 === 0;
  const male = input.gender === '男';
  const daXianClockwise = (yang && male) || (!yang && !male);
  const startAge = opts.daXianStartStyle === 'AgeOne' ? 1 : daXianStartAge(ju);
  for (let k = 0; k < 12; k++) {
    const pIdx = mod12(daXianClockwise ? k : -k);
    palaces[pIdx].daXianStart = startAge + 10 * k;
    palaces[pIdx].daXianEnd = startAge + 10 * k + 9;
  }

  // 16-17. 神煞 / 杂曜
  if (opts.showShenSha) computeShenSha(palaces, mingBranch, shenBranch, yearGan, yearBranch, chartMonth, hb, ld);
  if (opts.showExtraShenSha) computeExtraShenSha(palaces, mingBranch, shenBranch, yearGan, yearBranch, chartMonth, hb);

  // 18. 十二神
  if (opts.showTwelveShen) {
    const csStart = ({ 2: 8, 3: 11, 4: 5, 5: 8, 6: 2 } as Record<number, number>)[ju];
    placeTwelve(palaces, mingBranch, csStart, daXianClockwise, CHANG_SHENG_ORDER);
    placeTwelve(palaces, mingBranch, LU_CUN_BY_STEM[yearGan], daXianClockwise, BO_SHI_ORDER);
    // JIANG_XING 只有 4 个元素（三合中神），必须按三合组取，不能用 0-11 的年支直接下标
    placeTwelve(palaces, mingBranch, JIANG_XING[sanHeGroup(yearBranch)], true, JIANG_QIAN_ORDER);
  }

  // 19. 庙旺落陷
  if (opts.showBrightness) {
    for (const p of palaces) {
      for (const s of p.mainStars) {
        const idx = MAIN_STAR_NAMES.indexOf(s.name);
        if (idx >= 0) s.brightness = BRIGHTNESS_NAMES[BRIGHTNESS_TABLE[idx][DI_ZHI.indexOf(p.dizhi)]];
      }
    }
  }

  // 流年
  let liuNianMingIndex = -1;
  let liuNianSiHua: Record<string, string> = {};
  let douJunIndex = -1;
  if (opts.liuNianYear != null) {
    const lny = opts.liuNianYear;
    const lnBranch = (lny - 4) % 12;
    liuNianMingIndex = mod12(lnBranch - mingBranch);
    const lnGan = (lny - 4) % 10;
    const lnRow = (opts.siHuaStyle === 'ZhongZhou' ? SI_HUA_ZHONG_ZHOU : SI_HUA_NAN_PAI)[lnGan];
    liuNianSiHua = {};
    liuNianSiHua[lnRow[0]] = '禄'; liuNianSiHua[lnRow[1]] = '权'; liuNianSiHua[lnRow[2]] = '科'; liuNianSiHua[lnRow[3]] = '忌';
    if (opts.showLiuNianFull) {
      for (let k = 0; k < 12; k++) {
        const targetBranch = mod12(lnBranch - k);
        palaces[mod12(targetBranch - mingBranch)].liuNianName = PALACE_NAMES[k];
      }
    }
    douJunIndex = mod12(lnBranch - (chartMonth - 1) + hb);
    for (let k = 0; k < 12; k++) {
      const targetBranch = mod12(douJunIndex + k);
      palaces[mod12(targetBranch - mingBranch)].liuYue = k;
    }
  }

  // 小限 + 大限命宫四化
  let xiaoXianIndex = -1;
  let xiaoXianAge = -1;
  if (opts.currentAge != null) {
    const xiaoStart = opts.xiaoXianStyle === 'YearBranch' ? XIAO_XIAN_START_BY_BRANCH[yearBranch] : mingBranch;
    const offset = (opts.currentAge - 1) % 12;
    const fwd = male;
    xiaoXianIndex = mod12(xiaoStart + (fwd ? offset : -offset));
    xiaoXianAge = opts.currentAge;
    const baseYear = Math.floor((opts.currentAge - 1) / 12) * 12;
    for (let k = 0; k < 12; k++) {
      const br = mod12(xiaoStart + (fwd ? k : -k));
      palaces[mod12(br - mingBranch)].xiaoXianAge = baseYear + k + 1;
    }
  }
  // 19b. 小限全年龄 / 流年虚岁列表 / 限流叠宫（导出用，1-120 虚岁全周期）
  const xiaoStartFull = opts.xiaoXianStyle === 'YearBranch' ? XIAO_XIAN_START_BY_BRANCH[yearBranch] : mingBranch;
  for (let a = 1; a <= 120; a++) {
    const off = (a - 1) % 12;
    const xb = mod12(xiaoStartFull + (male ? off : -off));
    palaces[mod12(xb - mingBranch)].xiaoXianAges.push(a);
    const lb = mod12(yearBranch + a - 1);
    palaces[mod12(lb - mingBranch)].liuNianAges.push(a);
  }
  for (let i = 0; i < 12; i++) {
    const pBr = mod12(mingBranch + i);
    for (let a = palaces[i].daXianStart; a <= palaces[i].daXianEnd; a++) {
      const off = (a - 1) % 12;
      const xb = mod12(xiaoStartFull + (male ? off : -off));
      const lb = mod12(yearBranch + a - 1);
      if (xb === pBr && lb === pBr) palaces[i].dieGongAges.push(a);
    }
  }
  // 来因宫：生年干所落之宫；壬癸年两宫同干时，优先取与年支同宫者，否则取寅侧先到者
  let laiYinIndex = -1;
  const laiYinCandidates: number[] = [];
  for (let i = 0; i < 12; i++) {
    if (palaces[i].stem === TIAN_GAN[yearGan]) laiYinCandidates.push(i);
  }
  if (laiYinCandidates.length === 1) {
    laiYinIndex = laiYinCandidates[0];
  } else if (laiYinCandidates.length === 2) {
    const hit0 = palaces[laiYinCandidates[0]].dizhi === DI_ZHI[yearBranch];
    const hit1 = palaces[laiYinCandidates[1]].dizhi === DI_ZHI[yearBranch];
    laiYinIndex = hit0 ? laiYinCandidates[0] : (hit1 ? laiYinCandidates[1] : laiYinCandidates[0]);
  }
  let daXianMingIndex = -1;
  let daXianSiHua: Record<string, string> = {};
  if (opts.currentAge != null) {
    for (let i = 0; i < 12; i++) {
      if (opts.currentAge >= palaces[i].daXianStart && opts.currentAge <= palaces[i].daXianEnd) {
        daXianMingIndex = i;
        const dStem = TIAN_GAN.indexOf(palaces[i].stem);
        const dRow = (opts.siHuaStyle === 'ZhongZhou' ? SI_HUA_ZHONG_ZHOU : SI_HUA_NAN_PAI)[dStem];
        daXianSiHua = {};
        daXianSiHua[dRow[0]] = '禄'; daXianSiHua[dRow[1]] = '权'; daXianSiHua[dRow[2]] = '科'; daXianSiHua[dRow[3]] = '忌';
        break;
      }
    }
  }

  return {
    solarYear: solarY, solarMonth: solarM, solarDay: solarD,
    lunarYear: ly, lunarMonth: lm, lunarDay: ld, isLeap: isLeap, chartMonth: chartMonth,
    hour: input.hour, minute: minute, gender: input.gender, longitude: input.longitude ?? null, useTrueSolar: useLong,
    yearGanZhi: yearGz, monthGanZhi: monthGz, dayGanZhi: dayGz, hourGanZhi: hourGz,
    jieQiSiZhu: jieQiSiZhu, feiJieQiSiZhu: feiJieQiSiZhu, trueSolarHour: hourOfDay, laiYinIndex: laiYinIndex,
    yearGan: yearGan, yearBranch: yearBranch,
    mingGongIndex: 0, shenGongIndex: mod12(shenBranch - mingBranch), wuXingJu: WU_XING_JU_NAMES[ju - 2], wuXingJuNum: ju,
    ziWeiIndex: mod12(ziWeiBranch - mingBranch), tianFuIndex: mod12(tianFuBranch - mingBranch),
    palaces: palaces, siHua: siHua,
    mingZhu: MING_ZHU_BY_BRANCH[mingBranch], shenZhu: SHEN_ZHU_BY_BRANCH[yearBranch],
    liuNianYear: opts.liuNianYear, liuNianMingIndex: liuNianMingIndex, liuNianSiHua: liuNianSiHua,
    douJunIndex: douJunIndex >= 0 ? mod12(douJunIndex - mingBranch) : -1, daXianMingIndex: daXianMingIndex, daXianSiHua: daXianSiHua,
    xiaoXianIndex: xiaoXianIndex >= 0 ? mod12(xiaoXianIndex - mingBranch) : -1, xiaoXianAge: xiaoXianAge
  };
}
