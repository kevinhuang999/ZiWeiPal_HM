// 文墨天机样例盘外部对拍（1987-6-26 18:08 男，经度121）。
// 手抄自文墨天机 2.5.9 导出，作为引擎宫名/星曜/四化/大限的独立基准。
// 背景：09-12 发现十二宫宫名顺布错位（应逆布），以本样例逐宫对拍修正。
// 运行: node --experimental-strip-types tests/verify_wenmo.mts

import { buildChart, DEFAULT_OPTIONS } from './engine_node/ZiWeiEngine.ts';

interface Expect {
  name: string; dizhi: string; ganzhi: string;
  main: string[]; aux: string[]; daXian: [number, number];
  xiaoHead: number; lnHead: number;
}

// 文墨导出原文对照（主星只核名与亮度，辅星核名；自化单独断言）
const EXPECT: Expect[] = [
  { name: '命宫', dizhi: '戌', ganzhi: '庚戌', main: ['天机(利)', '天梁(庙)'], aux: [], daXian: [4, 13], xiaoHead: 10, lnHead: 8 },
  { name: '父母', dizhi: '亥', ganzhi: '辛亥', main: ['紫微(旺)', '七杀(平)'], aux: ['天魁'], daXian: [114, 123], xiaoHead: 11, lnHead: 9 },
  { name: '福德', dizhi: '子', ganzhi: '壬子', main: [], aux: [], daXian: [104, 113], xiaoHead: 12, lnHead: 10 },
  { name: '田宅', dizhi: '丑', ganzhi: '癸丑', main: [], aux: ['文昌', '文曲'], daXian: [94, 103], xiaoHead: 1, lnHead: 11 },
  { name: '官禄', dizhi: '寅', ganzhi: '壬寅', main: [], aux: ['地空'], daXian: [84, 93], xiaoHead: 2, lnHead: 12 },
  { name: '仆役', dizhi: '卯', ganzhi: '癸卯', main: ['廉贞(平)', '破军(陷)'], aux: [], daXian: [74, 83], xiaoHead: 3, lnHead: 1 },
  { name: '迁移', dizhi: '辰', ganzhi: '甲辰', main: [], aux: [], daXian: [64, 73], xiaoHead: 4, lnHead: 2 },
  { name: '疾厄', dizhi: '巳', ganzhi: '乙巳', main: ['天府(得)'], aux: ['右弼', '陀罗', '天马'], daXian: [54, 63], xiaoHead: 5, lnHead: 3 },
  { name: '财帛', dizhi: '午', ganzhi: '丙午', main: ['天同(陷)', '太阴(不)'], aux: ['禄存', '火星'], daXian: [44, 53], xiaoHead: 6, lnHead: 4 },
  { name: '子女', dizhi: '未', ganzhi: '丁未', main: ['武曲(庙)', '贪狼(庙)'], aux: ['擎羊', '铃星'], daXian: [34, 43], xiaoHead: 7, lnHead: 5 },
  { name: '夫妻', dizhi: '申', ganzhi: '戊申', main: ['太阳(得)', '巨门(庙)'], aux: ['地劫'], daXian: [24, 33], xiaoHead: 8, lnHead: 6 },
  { name: '兄弟', dizhi: '酉', ganzhi: '己酉', main: ['天相(陷)'], aux: ['左辅', '天钺'], daXian: [14, 23], xiaoHead: 9, lnHead: 7 },
];

const c = buildChart({
  solarYear: 1987, solarMonth: 6, solarDay: 26, hour: 18, minute: 8,
  gender: '男', longitude: 121, options: { ...DEFAULT_OPTIONS },
});
if (!c) {
  throw new Error('buildChart null');
}

let pass = 0;
let fail = 0;
function check(label: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fail++;
    console.log(`FAIL ${label}: got=${g} want=${w}`);
  }
}

check('来因宫', c.palaces[c.laiYinIndex]?.dizhi, '未');
check('身宫', c.palaces[c.shenGongIndex]?.dizhi, '辰');
check('天空落迁移（杂曜桶）', c.palaces.find((x) => x.palaceName === '迁移')?.shenSha.includes('天空'), true);
check('五行局', c.wuXingJu, '金四局');
check('命主', c.mingZhu, '禄存');
check('身主', c.shenZhu, '天同');
check('节气四柱', c.jieQiSiZhu, '丁卯 丙午 丙午 丁酉');
check('非节气四柱', c.feiJieQiSiZhu, '丁卯 丁未 丙午 丁酉');

// 十二宫逐宫：宫名↔干支对应、主星亮度、辅星、大限、小限/流年首值
// 亮度口径差：文墨失辉档用「不」，多数流派/本引擎用「陷」，对拍时视为等价
const norm = (s: string) => s.replace('(不)', '(陷)');
for (const e of EXPECT) {
  const p = c.palaces.find((x) => x.palaceName === e.name);
  if (!p) {
    fail++;
    console.log(`FAIL 找不到宫 ${e.name}`);
    continue;
  }
  check(`${e.name}.dizhi`, p.dizhi, e.dizhi);
  check(`${e.name}.ganzhi`, p.ganzhi, e.ganzhi);
  check(`${e.name}.主星`, p.mainStars.map((s) => norm(`${s.name}(${s.brightness})`)).sort(),
    e.main.map(norm).sort());
  check(`${e.name}.辅星`, p.auxStars.map((s) => s.name).sort(), [...e.aux].sort());
  check(`${e.name}.大限`, [p.daXianStart, p.daXianEnd], e.daXian);
  check(`${e.name}.小限首`, p.xiaoXianAges[0], e.xiaoHead);
  check(`${e.name}.流年首`, p.liuNianAges[0], e.lnHead);
}

// 生年四化（文墨标注）：财帛天同[权] 太阴[禄]；命宫天机[科]；夫妻巨门[忌]
function sihuaOf(palace: string, star: string): string {
  const p = c.palaces.find((x) => x.palaceName === palace);
  const s = p?.mainStars.find((x) => x.name === star);
  return s ? s.sihua : '';
}
check('财帛天同四化', sihuaOf('财帛', '天同'), '权');
check('财帛太阴四化', sihuaOf('财帛', '太阴'), '禄');
check('命宫天机四化', sihuaOf('命宫', '天机'), '科');
check('夫妻巨门四化', sihuaOf('夫妻', '巨门'), '忌');

// 自化（文墨）：交友破军[↓禄] 子女贪狼[↑忌] 父母紫微[↑科] 财帛天同[↓禄]
function selfOf(palace: string, star: string): string {
  const p = c.palaces.find((x) => x.palaceName === palace);
  const s = p?.mainStars.find((x) => x.name === star);
  return s ? s.selfSihua : '';
}
check('交友破军自化', selfOf('仆役', '破军'), '↓禄');
check('子女贪狼自化', selfOf('子女', '贪狼'), '↑忌');
check('父母紫微自化', selfOf('父母', '紫微'), '↑科');
check('财帛天同自化', selfOf('财帛', '天同'), '↓禄');

console.log(`文墨对拍: PASS=${pass} FAIL=${fail}`);
if (fail > 0) {
  process.exit(1);
}
