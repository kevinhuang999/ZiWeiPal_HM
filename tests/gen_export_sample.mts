// 在电脑上直跑引擎，生成「复制信息」的完整导出文案（与 App 内 buildMarkdown 同口径）。
// 用途：无真机时验证导出内容 / 喂给 AI 解析。仅本地使用，不参与 App 构建。
// 运行: node --experimental-strip-types tests/gen_export_sample.mts [年 月 日 时 分 性别 经度]
// 引擎镜像说明：tests/engine_node/*.ts 由 entry/src/main/ets/engine/*.ets 自动拷贝生成，
//   改引擎后需重新拷贝（见 README 或重跑生成命令）。

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { buildChart, DEFAULT_OPTIONS } from './engine_node/ZiWeiEngine.ts';
import { TIAN_GAN, DI_ZHI } from './engine_node/Constants.ts';
import { SI_HUA_NAN_PAI } from './engine_node/AnXingTables.ts';

const __dirname = dirname(fileURLToPath(import.meta.url));
const RES = join(__dirname, '..', 'entry', 'src', 'main', 'resources');

// ── 模拟 getStringSync：从 base 资源取值，%s 依序替换 ──
const raw = JSON.parse(readFileSync(join(RES, 'base', 'element', 'string.json'), 'utf8'));
const STR: Record<string, string> = {};
for (const it of raw['string'] as Array<{ name: string; value: string }>) {
  STR[it.name] = it.value;
}
function rs(name: string, ...args: string[]): string {
  let v = STR[name];
  if (v === undefined) {
    throw new Error(`缺少资源键: ${name}`);
  }
  for (const a of args) {
    v = v.replace('%s', a);
  }
  return v;
}

// ── 输入：文墨天机样例盘 1987-6-26 18:08 男，经度 121（可命令行覆盖）──
const a = process.argv.slice(2).map(Number);
const input = {
  solarYear: a[0] ?? 1987,
  solarMonth: a[1] ?? 6,
  solarDay: a[2] ?? 26,
  hour: a[3] ?? 18,
  minute: a[4] ?? 8,
  gender: a[5] !== undefined ? (a[5] === 1 ? '女' : '男') : '男',
  longitude: a[6] !== undefined ? a[6] : 121,
  options: { ...DEFAULT_OPTIONS },
};

const c = buildChart(input);
if (!c) {
  throw new Error('buildChart 返回 null');
}

// ── 大限/流年四化文案（与 ChartPage.siHuaText 同口径，南派默认）──
function siHuaText(gan: number): string {
  const row = SI_HUA_NAN_PAI[((gan % 10) + 10) % 10];
  return row[0] + '禄、' + row[1] + '权、' + row[2] + '科、' + row[3] + '忌';
}
function yearGzOf(y: number): string {
  return TIAN_GAN[(((y - 4) % 10) + 10) % 10] + DI_ZHI[(((y - 4) % 12) + 12) % 12];
}

// ── buildMarkdown 镜像（与 ChartPage.buildMarkdown 逐步对齐；简体模式无 hant 转换）──
type Star = { name: string; brightness: string; sihua: string; selfSihua: string };
type Cell = {
  palaceName: string; dizhi: string; ganzhi: string; stem: string;
  mainStars: Star[]; auxStars: Star[]; shenSha: string[];
  changSheng: string; boShi: string; jiangQian: string; suiQian: string;
  daXianStart: number; daXianEnd: number;
  xiaoXianAges: number[]; liuNianAges: number[]; dieGongAges: number[];
};

let s = rs('md_title') + '\n\n';
s += rs('md_gender', c.gender) + '\n';
const mm = c.minute < 10 ? '0' + c.minute : `${c.minute}`;
s += rs('md_clock', `${c.solarYear}-${c.solarMonth}-${c.solarDay} ${c.hour}:${mm}`) + '\n';
if (c.useTrueSolar && c.longitude != null) {
  const th = Math.floor(c.trueSolarHour);
  const tm = Math.round((c.trueSolarHour - th) * 60);
  const tms = tm < 10 ? '0' + tm : `${tm}`;
  const lon = `${Math.round(c.longitude * 100) / 100}`;
  s += rs('md_truesolar', `${c.solarYear}-${c.solarMonth}-${c.solarDay} ${th}:${tms}`, lon) + '\n';
}
const leap = c.isLeap ? rs('leap_suffix') : '';
s += rs('md_lunar', `${c.lunarYear}`, `${c.lunarMonth}`, `${c.lunarDay}`, leap) + '\n';
s += rs('md_sizhu', c.jieQiSiZhu) + '\n';
s += rs('md_sizhu_fn', c.feiJieQiSiZhu) + '\n';
s += rs('md_ju', c.wuXingJu, c.mingZhu, c.shenZhu) + '\n';
if (c.douJunIndex >= 0) {
  s += rs('md_doujun', c.palaces[c.douJunIndex].dizhi) + '\n';
}
s += rs('md_minggong', c.palaces[c.mingGongIndex].palaceName, c.palaces[c.mingGongIndex].dizhi) + '\n';
s += rs('md_shengong', c.palaces[c.shenGongIndex].palaceName, c.palaces[c.shenGongIndex].dizhi) + '\n';
if (c.laiYinIndex >= 0) {
  s += rs('md_laiyin', c.palaces[c.laiYinIndex].palaceName, c.palaces[c.laiYinIndex].ganzhi) + '\n';
}
s += rs('md_ziwei', c.palaces[c.ziWeiIndex].palaceName, c.palaces[c.tianFuIndex].palaceName) + '\n\n';
s += rs('md_palaces') + '\n\n';

const pal = c.palaces as Cell[];
for (const p of pal) {
  s += `### ${p.palaceName}（${p.dizhi} ${p.ganzhi}）\n`;
  if (p.mainStars.length) {
    s += rs('md_main') + p.mainStars.map((st) =>
      st.name + (st.brightness ? `(${st.brightness})` : '')
      + (st.sihua ? `[生年${st.sihua}]` : '')
      + (st.selfSihua ? `[${st.selfSihua}]` : '')).join('、') + '\n';
  }
  if (p.auxStars.length) {
    s += rs('md_aux') + p.auxStars.map((st) =>
      st.name + (st.sihua ? `[生年${st.sihua}]` : '')
      + (st.selfSihua ? `[${st.selfSihua}]` : '')).join('、') + '\n';
  }
  if (p.shenSha.length) {
    s += rs('md_shensha') + p.shenSha.join('、') + '\n';
  }
  if (p.changSheng) {
    s += rs('md_twelve', p.changSheng, p.boShi, p.jiangQian, p.suiQian) + '\n';
  }
  if (p.daXianStart >= 0) {
    s += rs('md_daxian', `${p.daXianStart}`, `${p.daXianEnd}`) + '\n';
  }
  if (p.xiaoXianAges.length) {
    s += rs('md_xiaoxian', p.xiaoXianAges.map((x) => `${x}`).join(',')) + '\n';
  }
  if (p.liuNianAges.length) {
    s += rs('md_ln_ages', p.liuNianAges.map((x) => `${x}`).join(',')) + '\n';
  }
  const die = p.dieGongAges.length
    ? p.dieGongAges.map((x) => `${x}虚岁(${c.lunarYear + x - 1})`).join('、')
    : rs('md_none');
  s += rs('md_diegong', die) + '\n\n';
}

// 大限流年信息（12 大限 × 各 10 流年）
s += rs('md_dx_title') + '\n\n';
const sorted: Cell[] = [...pal].sort((x, y) => x.daXianStart - y.daXianStart);
let no = 0;
for (const p of sorted) {
  if (p.daXianStart < 0) {
    continue;
  }
  no++;
  const y0 = c.lunarYear + p.daXianStart - 1;
  const y1 = c.lunarYear + p.daXianEnd - 1;
  s += `### ` + rs('md_dx_header', `${no}`, p.palaceName, p.ganzhi, `${y0}`, `${y1}`, `${p.daXianStart}`, `${p.daXianEnd}`) + '\n';
  const dStem = TIAN_GAN.indexOf(p.stem.charAt(0));
  s += rs('md_dx_sihua', siHuaText(dStem)) + '\n';
  for (let age = p.daXianStart; age <= p.daXianEnd; age++) {
    const yr = c.lunarYear + age - 1;
    const lnBranch = (((yr - 4) % 12) + 12) % 12;
    const lp = pal.find((pp) => pp.dizhi === DI_ZHI[lnBranch]);
    const lnGan = (((yr - 4) % 10) + 10) % 10;
    s += rs('md_ln_line', `${yr}`, yearGzOf(yr), `${age}`, lp ? lp.ganzhi : '-', siHuaText(lnGan)) + '\n';
  }
  s += '\n';
}

const out = join(__dirname, '..', '..', '..', 'deliverables',
  `ZiWeiPal_复制信息_${c.solarYear}${String(c.solarMonth).padStart(2, '0')}${String(c.solarDay).padStart(2, '0')}_${c.gender === '男' ? '男' : '女'}盘.md`);
writeFileSync(out, s, 'utf8');
console.log(`已生成: ${out}`);
console.log(`字符数: ${s.length}`);
console.log('--- 头部预览 ---');
console.log(s.split('\n').slice(0, 24).join('\n'));
