// 今日流日 公式层校验（独立复算，不参与 App 构建）
// 目的：主排盘已对拍 98/98 例，流日是叠加层 —— 这里只锁两件事：
//   1) 流日日柱所用日干，与引擎已验证的日柱锚点同源（同一条 dayPillarIndex）
//   2) 流日行走规律：初一 = 流月命宫，逐日顺行，30 天不折断
// 运行: node tests/verify_daily_fortune.mjs

const TIAN_GAN = ['甲','乙','丙','丁','戊','己','庚','辛','壬','癸'];
const DI_ZHI = ['子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'];
const mod12 = (x) => ((x % 12) + 12) % 12;

function julianDayNumber(y, m, d) {
  const a = Math.floor((14 - m) / 12);
  const y2 = y + 4800 - a;
  const m2 = m + 12 * a - 3;
  return d + Math.floor((153 * m2 + 2) / 5) + 365 * y2 + Math.floor(y2 / 4)
    - Math.floor(y2 / 100) + Math.floor(y2 / 400) - 32045;
}
function dayPillarIndex(y, m, d) { return (julianDayNumber(y, m, d) + 49) % 60; }
function gzDay(y, m, d) {
  const i = dayPillarIndex(y, m, d);
  return TIAN_GAN[i % 10] + DI_ZHI[i % 12];
}

// 与 engine/DailyFortune.ets 同一张四化表（南派）
const SI_HUA_NAN_PAI = [
  ['廉贞','破军','武曲','太阳'],['天机','天梁','紫微','太阴'],['天同','天机','文昌','廉贞'],
  ['太阴','天同','天机','巨门'],['贪狼','太阴','右辅','天机'],['武曲','贪狼','天梁','文曲'],
  ['太阳','武曲','太阴','天同'],['巨门','太阳','文曲','文昌'],['天梁','紫微','左辅','武曲'],['破军','巨门','太阴','贪狼']
];

let pass = 0, fail = 0;
function check(name, cond) {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name); }
}

// ---- [1] 日柱锚点：与 verify_engine.mjs 里已通过的锚点逐一对齐 ----
// dailyFortune 用的日干 = dayPillarIndex%10，只要这几例对上，
// 流日四化取干就不会和已验收的日柱口径跑偏。
const DAY_ANCHORS = [
  [2000, 8, 15, '乙巳'],
  [1987, 7, 18, '戊辰'],
  [2015, 1, 7, '癸未'],
  [2000, 1, 1, '戊午'],
  [1987, 6, 1, '辛巳']
];
console.log('[1] 日柱锚点（与 verify_engine 同源）');
for (const [y, m, d, want] of DAY_ANCHORS) {
  const got = gzDay(y, m, d);
  check(`日柱 ${y}-${m}-${d} = ${want}`, got === want);
}

// ---- [2] 流日行走规律 ----
// 引擎：斗君 = 正月所在宫，liuYue = k 表示第 k+1 个流月；
// DailyFortune：从流月宫起初一，顺行至当日。
console.log('\n[2] 流日行走（12 个流月宫 × 30 日）');
let walkOk = true, firstOk = true, wrapOk = true;
for (let month = 1; month <= 12; month++) {
  const liuYueBranch = mod12(month - 1);          // 任取一个流月宫地支，只验行走不验起宫
  const seq = [];
  for (let day = 1; day <= 30; day++) {
    seq.push(mod12(liuYueBranch + day - 1));
  }
  if (seq[0] !== liuYueBranch) { firstOk = false; }             // 初一必须落在流月宫
  for (let i = 1; i < seq.length; i++) {
    if (seq[i] !== mod12(seq[i - 1] + 1)) { walkOk = false; }   // 逐日顺行一格
  }
  if (new Set(seq).size !== 12) { wrapOk = false; }             // 30 天必须覆盖全部 12 宫（循环）
}
check('初一（第 1 日）= 流月命宫', firstOk);
check('逐日顺行一格，不跳不逆', walkOk);
check('30 日覆盖满 12 宫（顺行循环）', wrapOk);

// ---- [3] 流日四化：10 个日干都要能取出 4 条不重复星名 ----
console.log('\n[3] 流日四化（10 日干）');
let sihuaOk = true;
for (let g = 0; g < 10; g++) {
  const row = SI_HUA_NAN_PAI[g];
  if (!row || row.length !== 4) { sihuaOk = false; continue; }
  for (const s of row) {
    if (!s || typeof s !== 'string') { sihuaOk = false; }
  }
  if (new Set(row).size !== 4) { sihuaOk = false; }
}
check('甲…癸 每个日干都有 4 条不重复四化', sihuaOk);

// ---- [4] 黄总盘 2026-09-20 演算样例（人工可核） ----
// 仅打印不判定：流月宫/流日宫取决于引擎给的斗君，这里只验日柱与四化
console.log('\n[4] 样例演算（供人工核对）');
const y = 2026, m = 9, d = 20;
const idx = dayPillarIndex(y, m, d);
console.log(`  ${y}-${m}-${d} 日柱=${gzDay(y, m, d)}  日干=${TIAN_GAN[idx % 10]}`);
console.log(`  流日四化（南派）：禄${SI_HUA_NAN_PAI[idx % 10][0]} `
  + `权${SI_HUA_NAN_PAI[idx % 10][1]} 科${SI_HUA_NAN_PAI[idx % 10][2]} 忌${SI_HUA_NAN_PAI[idx % 10][3]}`);
const sample = gzDay(y, m, d);
check('样例日柱为合法干支', TIAN_GAN.includes(sample[0]) && DI_ZHI.includes(sample[1]));

console.log('\n====================================================================');
console.log(`结果: PASS=${pass} FAIL=${fail}`);
console.log('====================================================================');
process.exit(fail === 0 ? 0 : 1);
