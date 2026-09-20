// 安星查表（对齐 PC 版 ZiWei.Core/Tables）
// 所有索引：地支 0-11 = 子丑寅卯辰巳午未申酉戌亥；天干 0-9 = 甲乙丙丁戊己庚辛壬癸
import { MAIN_STAR_NAMES } from './Constants';

// 星系布星步数（ArkTS 不支持对象字面量类型，须显式声明 interface）
export interface StarStep {
  name: string;
  step: number;
}

// ========== 6.1 紫微星定位表（查表，非公式）============
// 行序 = 五行局-2（0=水二局 … 4=火六局）；列 = 农历日 1-30 → 紫微所在地支序
export const ZI_WEI_BY_DAY: number[][] = [
  // 水二局
  [1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 0, 0, 1, 1, 2, 2, 3, 3, 4],
  // 木三局
  [4, 1, 2, 5, 2, 3, 6, 3, 4, 7, 4, 5, 8, 5, 6, 9, 6, 7, 10, 7, 8, 11, 8, 9, 0, 9, 10, 1, 10, 11],
  // 金四局
  [11, 4, 1, 2, 0, 5, 2, 3, 1, 6, 3, 4, 2, 7, 4, 5, 3, 8, 5, 6, 4, 9, 6, 7, 5, 10, 7, 8, 6, 11],
  // 土五局
  [6, 11, 4, 1, 2, 7, 0, 5, 2, 3, 8, 1, 6, 3, 4, 9, 2, 7, 4, 5, 10, 3, 8, 5, 6, 11, 4, 9, 6, 7],
  // 火六局
  [9, 6, 11, 4, 1, 2, 10, 7, 0, 5, 2, 3, 11, 8, 1, 6, 3, 4, 0, 9, 2, 7, 4, 5, 1, 10, 3, 8, 5, 6]
];

// ========== 6.2 天府星定位（寅申同宫，其余对宫/轴对称）============
// 下标 = 紫微地支序 → 天府地支序
export const TIAN_FU_BY_ZI_WEI: number[] = [4, 3, 2, 1, 0, 11, 10, 9, 8, 7, 6, 5];

// ========== 6.3 紫微星系（相对紫微逆布步数）============
export const ZI_WEI_CLUSTER: StarStep[] = [
  { name: '天机', step: 1 },
  { name: '太阳', step: 3 },
  { name: '武曲', step: 4 },
  { name: '天同', step: 5 },
  // 口诀「又隔二位廉贞地，空三复见紫微郎」：天同退 5，空两位 → 廉贞退 8（原误作 7）
  { name: '廉贞', step: 8 }
];

// ========== 6.4 天府星系（相对天府顺布步数）============
export const TIAN_FU_CLUSTER: StarStep[] = [
  { name: '太阴', step: 1 },
  { name: '贪狼', step: 2 },
  { name: '巨门', step: 3 },
  { name: '天相', step: 4 },
  { name: '天梁', step: 5 },
  { name: '七杀', step: 6 },
  { name: '破军', step: 10 }
];

// ========== 6.5.1 辅星查表 ==========
// 禄存（年干 0-9）：寅卯巳午巳午申酉亥子  标准十干禄：甲寅 乙卯 丙戊巳 丁己午 庚申 辛酉 壬亥 癸子
export const LU_CUN_BY_STEM: number[] = [2, 3, 5, 6, 5, 6, 8, 9, 11, 0];
// 天魁天钺（年干 0-9 → [魁, 钺]）
export const KUI_YUE_BY_STEM: number[][] = [
  [1, 7], [0, 8], [11, 9], [11, 9], [1, 7], [0, 8], [1, 7], [6, 2], [3, 5], [3, 5]
];
// 天马（年支 0-11）：申子辰→寅、巳酉丑→亥、寅午戌→申、亥卯未→巳
export const TIAN_MA_BY_BRANCH: number[] = [2, 11, 8, 5, 2, 11, 8, 5, 2, 11, 8, 5];
// 火星起点（年支 0-11，起子时宫）
export const HUO_XING_START: number[] = [2, 3, 1, 9, 2, 3, 1, 9, 2, 3, 1, 9];
// 铃星起点（年支 0-11，起子时宫）
export const LING_XING_START: number[] = [10, 10, 3, 10, 10, 10, 3, 10, 10, 10, 3, 10];

// ========== 6.6 四化表（南派 / 中州派，按年干 → [禄,权,科,忌] 星名）============
export const SI_HUA_NAN_PAI: string[][] = [
  ['廉贞', '破军', '武曲', '太阳'],
  ['天机', '天梁', '紫微', '太阴'],
  ['天同', '天机', '文昌', '廉贞'],
  ['太阴', '天同', '天机', '巨门'],
  ['贪狼', '太阴', '右辅', '天机'],
  ['武曲', '贪狼', '天梁', '文曲'],
  ['太阳', '武曲', '太阴', '天同'],
  ['巨门', '太阳', '文曲', '文昌'],
  ['天梁', '紫微', '左辅', '武曲'],
  ['破军', '巨门', '太阴', '贪狼']
];
// 中州派仅戊/庚/壬三干不同
export const SI_HUA_ZHONG_ZHOU: string[][] = [
  ['廉贞', '破军', '武曲', '太阳'],
  ['天机', '天梁', '紫微', '太阴'],
  ['天同', '天机', '文昌', '廉贞'],
  ['太阴', '天同', '天机', '巨门'],
  ['贪狼', '太阴', '太阳', '天机'],   // 戊：科 右辅→太阳
  ['武曲', '贪狼', '天梁', '文曲'],
  ['太阳', '武曲', '天府', '天同'],   // 庚：科 太阴→天府
  ['巨门', '太阳', '文曲', '文昌'],
  ['天梁', '紫微', '天府', '武曲'],   // 壬：科 左辅→天府
  ['破军', '巨门', '太阴', '贪狼']
];

// ========== 6.7 五行局纳音取数 ==========
export function stemNumber(stem: number): number {
  return Math.floor(stem / 2) + 1; // 甲乙1 丙丁2 戊己3 庚辛4 壬癸5
}
export function branchNumber(br: number): number {
  // 子午丑未→1；寅申卯酉→2；辰戌巳亥→3
  if (br === 0 || br === 6 || br === 1 || br === 7) return 1;
  if (br === 2 || br === 8 || br === 3 || br === 9) return 2;
  return 3;
}
export function juFromNaYin(sum: number): number {
  let s = sum > 5 ? sum - 5 : sum;
  // 1木3 2金4 3水2 4火6 5(0)土5
  switch (s) {
    case 1: return 3;
    case 2: return 4;
    case 3: return 2;
    case 4: return 6;
    default: return 5;
  }
}

// ========== 6.8 大限起运岁 / 小限年支起宫 ==========
export function daXianStartAge(ju: number): number {
  return ju; // 水2 木3 金4 土5 火6
}
export const XIAO_XIAN_START_BY_BRANCH: number[] = [10, 7, 4, 1, 10, 7, 4, 1, 10, 7, 4, 1];

// ========== 6.9 命主 / 身主 ==========
export const MING_ZHU_BY_BRANCH: string[] = ['贪狼', '巨门', '禄存', '文曲', '廉贞', '武曲', '破军', '武曲', '廉贞', '文曲', '禄存', '巨门'];
export const SHEN_ZHU_BY_BRANCH: string[] = ['火星', '天相', '天梁', '天同', '文昌', '天机', '火星', '天相', '天梁', '天同', '文昌', '天机'];

// ========== 7. 庙旺落陷（14 主星 × 12 地支，0=庙 1=旺 2=得 3=利 4=平 5=不 6=陷）============
// 列序：子丑寅卯辰巳午未申酉戌亥
export const BRIGHTNESS_TABLE: number[][] = [
  [1, 0, 1, 1, 2, 1, 0, 0, 1, 1, 2, 1], // 紫微
  [0, 5, 2, 1, 3, 4, 0, 5, 2, 1, 3, 4], // 天机
  [6, 5, 1, 0, 1, 1, 1, 2, 2, 4, 5, 6], // 太阳
  [1, 0, 2, 3, 0, 4, 1, 0, 2, 3, 0, 4], // 武曲
  [1, 5, 3, 4, 4, 0, 6, 6, 1, 4, 4, 0], // 天同
  [4, 3, 0, 4, 3, 6, 4, 3, 0, 4, 3, 6], // 廉贞
  [0, 0, 0, 2, 0, 2, 2, 0, 2, 1, 0, 2], // 天府
  [0, 0, 1, 6, 6, 6, 6, 5, 3, 1, 1, 0], // 太阴
  [1, 0, 4, 3, 0, 6, 1, 0, 4, 3, 0, 6], // 贪狼
  [1, 5, 0, 0, 6, 1, 1, 5, 0, 0, 6, 1], // 巨门
  [0, 0, 0, 6, 2, 2, 0, 2, 0, 6, 2, 2], // 天相
  [0, 1, 0, 0, 0, 2, 0, 1, 6, 6, 0, 6], // 天梁
  [1, 0, 0, 1, 0, 4, 1, 0, 0, 1, 0, 4], // 七杀
  [0, 1, 2, 6, 1, 4, 0, 1, 2, 6, 1, 4]  // 破军
];

// ========== 9. 星曜属性（14 主星）============
export interface StarAttr {
  wx: string; // 五行
  yy: string; // 阴阳
  hq: string; // 化气
}
export const STAR_ATTRIBUTE: StarAttr[] = [
  { wx: '土', yy: '阳', hq: '尊' },
  { wx: '木', yy: '阴', hq: '善' },
  { wx: '火', yy: '阳', hq: '贵' },
  { wx: '金', yy: '阴', hq: '财' },
  { wx: '水', yy: '阳', hq: '福' },
  { wx: '火', yy: '阴', hq: '囚' },
  { wx: '土', yy: '阳', hq: '库' },
  { wx: '水', yy: '阴', hq: '富' },
  { wx: '木', yy: '阳', hq: '桃花' },
  { wx: '水', yy: '阴', hq: '暗' },
  { wx: '水', yy: '阳', hq: '印' },
  { wx: '土', yy: '阳', hq: '荫' },
  { wx: '金', yy: '阳', hq: '将' },
  { wx: '水', yy: '阴', hq: '耗' }
];

// ========== 8.2 神煞基础分组 ==========
// 三合：0=申子辰(0,4,8) 1=寅午戌(2,6,10) 2=巳酉丑(1,5,9) 3=亥卯未(3,7,11)
export function sanHeGroup(br: number): number {
  if (br === 0 || br === 4 || br === 8) return 0;
  if (br === 2 || br === 6 || br === 10) return 1;
  if (br === 1 || br === 5 || br === 9) return 2;
  return 3;
}
// 年支四局：亥子丑0 寅卯辰1 巳午未2 申酉戌3
export function yearSiJu(br: number): number {
  if (br === 11 || br === 0 || br === 1) return 0;
  if (br === 2 || br === 3 || br === 4) return 1;
  if (br === 5 || br === 6 || br === 7) return 2;
  return 3;
}
// 咸池（三合桃花）：group→酉(9) 卯(3) 午(6) 子(0)
export const XIAN_CHI: number[] = [9, 3, 6, 0];
// 华盖（三合墓库）：group→辰(4) 戌(10) 丑(1) 未(7)
export const HUA_GAI: number[] = [4, 10, 1, 7];
// 将星（三合中神）：group→子(0) 午(6) 酉(9) 卯(3)
export const JIANG_XING: number[] = [0, 6, 9, 3];
// 孤辰（四局）：局0→寅(2) 1→巳(5) 2→申(8) 3→亥(11)
export const GU_CHEN: number[] = [2, 5, 8, 11];
// 寡宿（四局）：局0→戌(10) 1→丑(1) 2→辰(4) 3→未(7)
export const GUA_SU: number[] = [10, 1, 4, 7];
// 天德（月系 chartMonth 1-12）
export const TIAN_DE: number[] = [6, 8, 11, 9, 11, 2, 0, 2, 5, 3, 5, 8];
// 月德（月系）：monthBranch 三合→亥(10) 巳(5) 申(8) 寅(2)
export const YUE_DE: number[] = [10, 5, 8, 2];
// 天月（月系硬编码）：正月戌…十二月寅
export const TIAN_YUE: number[] = [10, 5, 4, 2, 7, 3, 11, 7, 2, 6, 10, 2];
// 天巫（月系，四组循环）：正五九月巳(5) 二六十月申(8) 三七十一寅(2) 四八十二亥(11)
export const TIAN_WU_BY_MONTH: number[] = [5, 8, 2, 11];
// 天官贵人（年干 0-9）：甲未7 乙辰4 丙巳5 丁寅2 戊卯3 己酉9 庚亥11 辛酉9 壬戌10 癸午6
export const TIAN_GUAN_BY_STEM: number[] = [7, 4, 5, 2, 3, 9, 11, 9, 10, 6];
// 天福贵人（年干 0-9）：甲酉9 乙申8 丙子0 丁亥11 戊卯3 己寅2 庚午6 辛巳5 壬午6 癸巳5
export const TIAN_FU_GUI_BY_STEM: number[] = [9, 8, 0, 11, 3, 2, 6, 5, 6, 5];

// ========== 12. 出生地城市经度库（部分，东经度数）============
export interface GeoCity {
  cn: string;
  en: string;
  lon: number;
}
export const GEO_CITIES: GeoCity[] = [
  { cn: '北京', en: 'Beijing', lon: 116.41 },
  { cn: '上海', en: 'Shanghai', lon: 121.47 },
  { cn: '天津', en: 'Tianjin', lon: 117.20 },
  { cn: '重庆', en: 'Chongqing', lon: 106.55 },
  { cn: '南京', en: 'Nanjing', lon: 118.78 },
  { cn: '苏州', en: 'Suzhou', lon: 120.58 },
  { cn: '无锡', en: 'Wuxi', lon: 120.31 },
  { cn: '常州', en: 'Changzhou', lon: 119.97 },
  { cn: '镇江', en: 'Zhenjiang', lon: 119.42 },
  { cn: '南通', en: 'Nantong', lon: 120.86 },
  { cn: '海门', en: 'Haimen', lon: 121.15 },
  { cn: '启东', en: 'Qidong', lon: 121.66 },
  { cn: '如皋', en: 'Rugao', lon: 120.77 },
  { cn: '扬州', en: 'Yangzhou', lon: 119.42 },
  { cn: '泰州', en: 'Taizhou', lon: 119.92 },
  { cn: '徐州', en: 'Xuzhou', lon: 117.28 },
  { cn: '盐城', en: 'Yancheng', lon: 120.16 },
  { cn: '淮安', en: 'Huaian', lon: 119.02 },
  { cn: '连云港', en: 'Lianyungang', lon: 119.22 },
  { cn: '宿迁', en: 'Suqian', lon: 118.28 },
  { cn: '广州', en: 'Guangzhou', lon: 113.26 },
  { cn: '深圳', en: 'Shenzhen', lon: 114.06 },
  { cn: '成都', en: 'Chengdu', lon: 104.07 },
  { cn: '武汉', en: 'Wuhan', lon: 114.30 },
  { cn: '西安', en: 'Xian', lon: 108.95 },
  { cn: '杭州', en: 'Hangzhou', lon: 120.15 },
  { cn: '宁波', en: 'Ningbo', lon: 121.55 },
  { cn: '温州', en: 'Wenzhou', lon: 120.70 },
  { cn: '福州', en: 'Fuzhou', lon: 119.30 },
  { cn: '厦门', en: 'Xiamen', lon: 118.10 },
  { cn: '南昌', en: 'Nanchang', lon: 115.86 },
  { cn: '长沙', en: 'Changsha', lon: 112.94 },
  { cn: '青岛', en: 'Qingdao', lon: 120.38 },
  { cn: '济南', en: 'Jinan', lon: 117.00 },
  { cn: '郑州', en: 'Zhengzhou', lon: 113.62 },
  { cn: '合肥', en: 'Hefei', lon: 117.23 },
  { cn: '昆明', en: 'Kunming', lon: 102.71 },
  { cn: '贵阳', en: 'Guiyang', lon: 106.63 },
  { cn: '哈尔滨', en: 'Harbin', lon: 126.53 },
  { cn: '沈阳', en: 'Shenyang', lon: 123.43 },
  { cn: '大连', en: 'Dalian', lon: 121.62 },
  { cn: '石家庄', en: 'Shijiazhuang', lon: 114.51 },
  { cn: '太原', en: 'Taiyuan', lon: 112.55 },
  { cn: '兰州', en: 'Lanzhou', lon: 103.83 },
  { cn: '南宁', en: 'Nanning', lon: 108.32 },
  { cn: '海口', en: 'Haikou', lon: 110.20 },
  { cn: '香港', en: 'HongKong', lon: 114.17 },
  { cn: '澳门', en: 'Macau', lon: 113.54 },
  { cn: '台北', en: 'Taipei', lon: 121.50 }
];
