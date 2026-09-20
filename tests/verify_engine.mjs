// 引擎校验 v2（对齐 PC 版锚点 + 倪师 38 例穷举反推）。独立复算，捕获表/公式转录错误。
// 仅用于本地验证，不参与 App 构建。
// 运行: node tests/verify_engine.mjs

const TIAN_GAN = ['甲','乙','丙','丁','戊','己','庚','辛','壬','癸'];
const DI_ZHI = ['子','丑','寅','卯','辰','巳','午','未','申','酉','戌','亥'];
const PALACE_NAMES = ['命宫','兄弟','夫妻','子女','财帛','疾厄','迁移','仆役','官禄','田宅','福德','父母'];
const mod12 = (x) => ((x % 12) + 12) % 12;

// 紫微定位表（与 AnXingTables 同源）
const ZI_WEI_BY_DAY = [
  [1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,0,0,1,1,2,2,3,3,4],
  [4,1,2,5,2,3,6,3,4,7,4,5,8,5,6,9,6,7,10,7,8,11,8,9,0,9,10,1,10,11],
  [11,4,1,2,0,5,2,3,1,6,3,4,2,7,4,5,3,8,5,6,4,9,6,7,5,10,7,8,6,11],
  [6,11,4,1,2,7,0,5,2,3,8,1,6,3,4,9,2,7,4,5,10,3,8,5,6,11,4,9,6,7],
  [9,6,11,4,1,2,10,7,0,5,2,3,11,8,1,6,3,4,0,9,2,7,4,5,1,10,3,8,5,6]
];
const TIAN_FU_BY_ZI_WEI = [4,3,2,1,0,11,10,9,8,7,6,5];
// 紫微系逆布步数（0=紫微本身）: 天机1 太阳3 武曲4 天同5 廉贞7
const ZI_WEI_CLUSTER = [['天机',1],['太阳',3],['武曲',4],['天同',5],['廉贞',7]];
// 天府系顺布步数: 太阴1 贪狼2 巨门3 天相4 天梁5 七杀6 破军10
const TIAN_FU_CLUSTER = [['太阴',1],['贪狼',2],['巨门',3],['天相',4],['天梁',5],['七杀',6],['破军',10]];
const SI_HUA_NAN_PAI = [
  ['廉贞','破军','武曲','太阳'],['天机','天梁','紫微','太阴'],['天同','天机','文昌','廉贞'],
  ['太阴','天同','天机','巨门'],['贪狼','太阴','右辅','天机'],['武曲','贪狼','天梁','文曲'],
  ['太阳','武曲','太阴','天同'],['巨门','太阳','文曲','文昌'],['天梁','紫微','左辅','武曲'],['破军','巨门','太阴','贪狼']
];
const SI_HUA_ZHONG_ZHOU = SI_HUA_NAN_PAI.map((r,i)=> i===4?['贪狼','太阴','太阳','天机']: i===6?['太阳','武曲','天府','天同']: i===8?['天梁','紫微','天府','武曲']: r);
// 辅星表（黄总盘用）
const LU_CUN_BY_STEM = [6,6,4,4,2,2,0,0,10,10];        // 甲己辰? 甲=寅? 按支序: 甲寅? 修正见下
// 实测 PC: 黄总丁年 禄存午(6)。丁=4 -> LU_CUN_BY_STEM[4]=2? 需对齐: 甲巳(5)乙巳(5)丙申(8)丁午(6)戊巳(5)己午(6)庚申(8)辛酉(9)壬亥(11)癸子(0)
const LU_CUN2 = [5,5,8,6,5,6,8,9,11,0];
const KUI_YUE_BY_STEM = [ // [天魁,天钺] 甲[丑,未]乙[子,申]丙[亥,酉]丁[亥,酉]戊[丑,未]己[子,申]庚[丑,未]辛[午,寅]壬[卯,巳]癸[卯,巳]
  [1,7],[0,8],[11,9],[11,9],[1,7],[0,8],[1,7],[6,2],[3,5],[3,5]];
const TIAN_MA_BY_BRANCH = [ // 子寅,丑亥,寅申,卯巳,辰寅,巳亥,午申,未巳,申寅,酉亥,戌申,亥巳
  2,11,8,5,2,11,8,5,2,11,8,5];
const HUO_XING_START = [2,3,1,9,2,3,1,9,2,3,1,9];  // 年支→火星子时起点（申子辰寅/巳酉丑卯/寅午戌丑/亥卯未酉）
const LING_XING_START = [10,10,3,10,10,10,3,10,10,10,3,10]; // 年支→铃星子时起点（申子辰戌/巳酉丑戌/寅午戌卯/亥卯未戌）

function stemNumber(s){return Math.floor(s/2)+1;}
function branchNumber(b){ if(b===0||b===6||b===1||b===7)return 1; if(b===2||b===8||b===3||b===9)return 2; return 3; }
function juFromNaYin(sum){ let s=sum>5?sum-5:sum; return s===1?3:s===2?4:s===3?2:s===4?6:5; }

function julianDayNumber(y,m,d){ const a=Math.floor((14-m)/12); const y2=y+4800-a; const m2=m+12*a-3; return d+Math.floor((153*m2+2)/5)+365*y2+Math.floor(y2/4)-Math.floor(y2/100)+Math.floor(y2/400)-32045; }
function dayPillarIndex(y,m,d){ return (julianDayNumber(y,m,d)+49)%60; }
function gzYear(year){ return TIAN_GAN[((year-4)%10+10)%10]+DI_ZHI[((year-4)%12+12)%12]; }
function monthPillarByStem(ys,cm){ const z=(ys*2+2)%10; const stem=(z+cm-1)%10; const branch=(2+cm-1)%12; return TIAN_GAN[stem]+DI_ZHI[branch]; }
function hourPillar(ds,hb){ const z=(ds%5)*2; return TIAN_GAN[(z+hb)%10]+DI_ZHI[hb]; }
function computeChartMonth(lm,isLeap,ld,style){ if(!isLeap)return lm; if(style==='WholePrev')return lm; if(style==='WholeNext')return lm+1; return ld<=15?lm:lm+1; }

// 排盘（农历输入）——返回全部可复算字段
function build({ly,lm,ld,isLeap=false,hour,gender,chartMonthStyle='HalfMonth',siHuaStyle='NanPai'}){
  const chartMonth=computeChartMonth(lm,isLeap,ld,chartMonthStyle);
  const hb = (Math.floor((hour+1)/2))%12;
  const yearGz=gzYear(ly); const yearGan=TIAN_GAN.indexOf(yearGz[0]); const yearBranch=DI_ZHI.indexOf(yearGz[1]);
  const monthGz=monthPillarByStem(yearGan,chartMonth);
  const di=dayPillarIndex(ly,lm,ld);
  const dayGz=TIAN_GAN[di%10]+DI_ZHI[di%12]; const dayStem=di%10; const hourGz=hourPillar(dayStem,hb);
  const monthPos=mod12(2+chartMonth-1); const mingBranch=mod12(monthPos-hb); const shenBranch=mod12(monthPos+hb);
  const yinStem=(yearGan*2+2)%10;
  const mingStem=(yinStem+mod12(mingBranch-2))%10;
  const naYinSum=stemNumber(mingStem)+branchNumber(mingBranch); const ju=juFromNaYin(naYinSum);
  const ziWei=ZI_WEI_BY_DAY[ju-2][ld-1]; const tianFu=TIAN_FU_BY_ZI_WEI[ziWei];
  // 14 主星落宫（地支序）
  const mainStars={};
  mainStars['紫微']=ziWei; mainStars['天府']=tianFu;
  for(const [nm,step] of ZI_WEI_CLUSTER) mainStars[nm]=mod12(ziWei-step);
  for(const [nm,step] of TIAN_FU_CLUSTER) mainStars[nm]=mod12(tianFu+step);
  // 辅星
  const auxStars={};
  // 左辅(辰起正月顺) 右弼(戌起正月逆)
  auxStars['左辅']=mod12(4+(chartMonth-1));
  auxStars['右弼']=mod12(10-(chartMonth-1));
  // 文昌文曲(时): 文昌戌起子时顺, 文曲辰起子时逆
  auxStars['文昌']=mod12(10+hb); auxStars['文曲']=mod12(4-hb);
  // 天魁天钺(年干)
  auxStars['天魁']=KUI_YUE_BY_STEM[yearGan][0]; auxStars['天钺']=KUI_YUE_BY_STEM[yearGan][1];
  // 禄存(年干) 擎羊陀罗
  const lucun=LU_CUN2[yearGan];
  auxStars['禄存']=lucun; auxStars['擎羊']=mod12(lucun+1); auxStars['陀罗']=mod12(lucun-1);
  // 火星铃星(年支+时): 起子时宫位顺数至生时
  auxStars['火星']=mod12(HUO_XING_START[yearBranch]+hb);
  auxStars['铃星']=mod12(LING_XING_START[yearBranch]+hb);
  // 天马(年支三合)
  auxStars['天马']=TIAN_MA_BY_BRANCH[yearBranch];
  // 四化
  const row=siHuaStyle==='NanPai'?SI_HUA_NAN_PAI[yearGan]:SI_HUA_ZHONG_ZHOU[yearGan];
  const siHua={}; row.forEach((nm,i)=>siHua[nm]=['禄','权','科','忌'][i]);
  // 大限: 局数=起运年龄; 阳男阴女顺 阴男阳女逆（甲丙戊庚壬=偶索引=阳）
  const yang = (yearGan % 2 === 0) ? 1 : 0; // 0=阴 1=阳
  const male=gender==='男'?1:0;
  const clockwise=(yang===1 && male===1)||(yang===0 && male===0);
  const daXianStart=ju;
  return {yearGz,monthGz,dayGz,hourGz,mingBranch,shenBranch,ju,wuXing:['水二局','木三局','金四局','土五局','火六局'][ju-2],ziWei,tianFu,mainStars,auxStars,siHua,clockwise,daXianStart};
}

let pass=0, fail=0;
function check(name, got, exp){ const ok=JSON.stringify(got)===JSON.stringify(exp); console.log((ok?'PASS':'FAIL')+' '+name+'  got='+JSON.stringify(got)+(ok?'':' exp='+JSON.stringify(exp))); ok?pass++:fail++; }

// ============ 锚点组 1：壬子年十二月初三戌时（PC 原锚点） ============
const a1=build({ly:1972,lm:12,ld:3,hour:20,gender:'男'});
check('壬子 命宫=卯', DI_ZHI[a1.mingBranch], '卯');
check('壬子 身宫=亥', DI_ZHI[a1.shenBranch], '亥');
check('壬子 五行局=金四局', a1.wuXing, '金四局');
check('壬子 紫微=丑', DI_ZHI[a1.ziWei], '丑');
check('壬子 天府=卯', DI_ZHI[a1.tianFu], '卯');

// ============ 锚点组 2：日柱 ============
function dp(y,m,d){ const i=dayPillarIndex(y,m,d); return TIAN_GAN[i%10]+DI_ZHI[i%12]; }
check('日柱 2000-08-15', dp(2000,8,15), '乙巳');
check('日柱 1987-07-18', dp(1987,7,18), '戊辰');
check('日柱 2015-01-07', dp(2015,1,7), '癸未');
check('日柱 2000-01-01', dp(2000,1,1), '戊午');
check('日柱 1987-06-01', dp(1987,6,1), '辛巳'); // PC: 黄总日柱辛巳

// ============ 锚点组 3：四化流派（庚年差异） ============
const geng=build({ly:1980,lm:1,ld:1,hour:0,gender:'男'}); // 1980=庚申
check('庚年 南派科=太阴', geng.siHua['太阴'], '科');
const gengZ=build({ly:1980,lm:1,ld:1,hour:0,gender:'男',siHuaStyle:'ZhongZhou'});
check('庚年 中州科=天府', gengZ.siHua['天府'], '科');
check('庚年 中州无太阴科', gengZ.siHua['太阴'], undefined);
// 戊年（戊=4? 戊=4 辛=7 壬=8）: 南派 贪狼太阴右辅天机; 中州 贪狼太阴太阳天机
const wu=build({ly:1988,lm:1,ld:1,hour:0,gender:'男'}); // 1988=戊辰
check('戊年 南派禄=贪狼', wu.siHua['贪狼'], '禄');
const wuZ=build({ly:1988,lm:1,ld:1,hour:0,gender:'男',siHuaStyle:'ZhongZhou'});
check('戊年 中州科=太阳', wuZ.siHua['太阳'], '科');
// 壬年: 南派 天梁紫微左辅武曲; 中州 天梁紫微天府武曲
const ren=build({ly:1972,lm:1,ld:1,hour:0,gender:'男'}); // 1972=壬子
check('壬年 南派科=左辅', ren.siHua['左辅'], '科');
const renZ=build({ly:1972,lm:1,ld:1,hour:0,gender:'男',siHuaStyle:'ZhongZhou'});
check('壬年 中州科=天府', renZ.siHua['天府'], '科');

// ============ 锚点组 4：闰月 chartMonth ============
check('闰六 ld15→chartMonth6', computeChartMonth(6,true,15,'HalfMonth'), 6);
check('闰六 ld16→chartMonth7', computeChartMonth(6,true,16,'HalfMonth'), 7);

// ============ 锚点组 5：黄总盘（丁卯六月初一酉时男）全星逐颗 ============
const hz=build({ly:1987,lm:6,ld:1,hour:18,gender:'男'});
console.log('\n黄总盘: 年='+hz.yearGz+' 月='+hz.monthGz+' 日='+hz.dayGz+' 时='+hz.hourGz+
  ' 命宫='+DI_ZHI[hz.mingBranch]+' 身宫='+DI_ZHI[hz.shenBranch]+' '+hz.wuXing+' 大限'+(hz.clockwise?'顺':'逆')+'行 '+hz.daXianStart+'岁起');
check('黄总 年柱', hz.yearGz, '丁卯');
check('黄总 月柱', hz.monthGz, '丁未');
check('黄总 日柱', hz.dayGz, '辛巳');
check('黄总 时柱', hz.hourGz, '丁酉');
check('黄总 命宫=戌', DI_ZHI[hz.mingBranch], '戌');
check('黄总 身宫=辰', DI_ZHI[hz.shenBranch], '辰');
check('黄总 五行局=金四局', hz.wuXing, '金四局');
check('黄总 大限逆行', hz.clockwise, false);
check('黄总 大限4岁起', hz.daXianStart, 4);
// 14 主星（PC ChartBuilderTests 断言值）
const hzExpMain={'紫微':'亥','天府':'巳','天机':'戌','太阳':'申','武曲':'未','天同':'午','廉贞':'辰','太阴':'午','贪狼':'未','巨门':'申','天相':'酉','天梁':'戌','七杀':'亥','破军':'卯'};
for(const nm of Object.keys(hzExpMain)) check('黄总 主星'+nm, DI_ZHI[hz.mainStars[nm]], hzExpMain[nm]);
// 辅星（PC 断言值）
const hzExpAux={'左辅':'酉','右弼':'巳','天魁':'亥','天钺':'酉','禄存':'午','擎羊':'未','陀罗':'巳','火星':'午','铃星':'未','天马':'巳'};
for(const nm of Object.keys(hzExpAux)) check('黄总 辅星'+nm, DI_ZHI[hz.auxStars[nm]], hzExpAux[nm]);
// 四化（丁年: 太阴禄 天同权 天机科 巨门忌）
check('黄总 四化太阴禄', hz.siHua['太阴'], '禄');
check('黄总 四化天同权', hz.siHua['天同'], '权');
check('黄总 四化天机科', hz.siHua['天机'], '科');
check('黄总 四化巨门忌', hz.siHua['巨门'], '忌');

// ============ 锚点组 6：倪师《天纪》38 例穷举反推（命宫/五行局/紫微三锚点） ============
// 数据: [编号, 公历年, 农历日, 时支序, 性别, 图上五行局(ju序号), 图上紫微宫, 图上命宫]
const NISHI = [
  [21,1965,28,4,'男',3,1,7],[22,1947,7,5,'男',4,2,2],[23,1955,5,7,'男',2,3,8],
  [24,1967,2,3,'女',4,4,11],[25,1994,19,5,'女',4,5,9],[26,1969,2,5,'男',6,6,11],
  [27,1957,10,6,'女',3,7,1],[28,1951,15,8,'男',2,8,4],[29,1961,24,4,'男',3,9,3],
  [30,1957,29,2,'男',3,10,0],[31,1949,3,1,'女',6,11,11],[32,1948,25,3,'男',3,0,9],
  [34,1955,14,8,'女',3,5,7],[35,1953,3,1,'男',2,2,10],[36,1958,11,11,'男',6,2,7],
  [37,1957,15,6,'女',2,8,6],[38,1962,23,10,'男',6,4,4],[39,1961,5,10,'女',4,0,6],
  [40,1994,19,5,'女',4,5,9],[41,1948,11,7,'女',5,8,5],[42,1965,28,4,'男',3,1,7],
  [43,1957,4,8,'女',4,2,11],[44,1952,2,4,'女',5,11,8],[45,1966,29,6,'女',3,10,11],
  [46,1945,3,0,'男',5,4,10],[47,1957,29,2,'男',3,10,0],[48,1944,11,2,'女',3,4,4],
  [50,1939,30,5,'男',4,11,9],[51,1952,28,1,'女',5,9,9],[52,1952,19,7,'女',6,0,4],
  [53,1929,8,4,'男',2,5,1],[54,1960,25,0,'男',2,1,8],[55,1942,21,8,'女',4,4,3],
  [56,1949,28,5,'女',4,8,9],[57,1928,17,3,'女',5,2,5],[58,1939,11,3,'女',4,3,8],
  [59,1941,30,0,'女',5,7,0],[60,1939,5,9,'女',6,1,2]
];
// 时支序→代表时刻（PC HourOf = 支序*2）
const hourOf=(b)=>b*2;
let nishiPass=0, nishiFail=0;
for(const [no,yr,day,hb,g,expJu,expZw,expMg] of NISHI){
  let matched=null; const mingMatches=[];
  for(let m=1;m<=12;m++){
    let r;
    try{ r=build({ly:yr,lm:m,ld:day,hour:hourOf(hb),gender:g}); }catch(e){ continue; }
    if(r.mingBranch!==expMg) continue;
    mingMatches.push(m);
    if(r.ju===expJu && r.ziWei===expZw){ matched=m; break; }
  }
  const ok=matched!==null;
  if(ok) nishiPass++; else { nishiFail++; console.log('FAIL 倪师'+no+' 无匹配 命宫吻合月份=['+mingMatches.join(',')+'] 期望(局='+expJu+' 紫微='+DI_ZHI[expZw]+' 命宫='+DI_ZHI[expMg]+')'); }
}
console.log('倪师38例: PASS='+nishiPass+' FAIL='+nishiFail);
pass+=nishiPass; fail+=nishiFail;

// ============ 锚点组 7：真太阳时均时差 ============
function eotMinutes(dayOfYear){
  const B=2*Math.PI*(dayOfYear-81)/364;
  return 9.87*Math.sin(2*B)-7.53*Math.cos(B)-1.5*Math.sin(B);
}
function dayOfYear(y,m,d){ const days=[0,31,28,31,30,31,30,31,31,30,31,30,31]; let t=d; for(let i=1;i<m;i++)t+=days[i]; if(m>2&&((y%4===0&&y%100!==0)||y%400===0))t++; return t; }
check('均时差 2月11日 ≈ -14.2', Math.abs(eotMinutes(dayOfYear(2024,2,11))-(-14.2))<=2, true);
check('均时差 11月3日 ≈ +16.4', Math.abs(eotMinutes(dayOfYear(2024,11,3))-16.4)<=2, true);
// 真太阳时跨时辰边界: 2024农历11月3日≈公历12月, EoT≈+9 + 经度121.47(+5.9min) → 16:50申→酉
function trueSolarHour(stdHour,lon,doy){ return stdHour+(lon-120)*4/60+eotMinutes(doy)/60; }
const tsH=trueSolarHour(16+50/60,121.47,dayOfYear(2024,12,3));
check('真太阳时 16:50→酉时', Math.floor((tsH+1)/2)%12===9 || Math.floor(tsH/2)===9, true);
console.log('  (16:50+校正 = '+tsH.toFixed(3)+'h = '+DI_ZHI[Math.floor((tsH+1)/2)%12]+'时)');

// ============ 锚点组 8：四柱/命身宫/局交叉（随机批 50 组自洽性） ============
// 命宫身宫: 命=月-时, 身=月+时; 两宫必相对或同宫特性（月位置=2+cm-1）
let selfOk=true;
for(let i=0;i<50;i++){
  const ly=1950+Math.floor(Math.random()*60), lm=1+Math.floor(Math.random()*12), ld=1+Math.floor(Math.random()*28);
  const hour=Math.floor(Math.random()*24);
  const r=build({ly,lm,ld,hour,gender:i%2?'男':'女'});
  // 自洽: 紫微与天府必成对宫关系 TIAN_FU_BY_ZI_WEI
  if(TIAN_FU_BY_ZI_WEI[r.ziWei]!==r.tianFu){ selfOk=false; break; }
  // 主星数=14
  if(Object.keys(r.mainStars).length!==14){ selfOk=false; break; }
}
check('随机50组 紫微-天府对宫关系+主星14颗', selfOk, true);

// ============ 汇总 ============
console.log('\n结果: PASS='+pass+' FAIL='+fail);
process.exit(fail>0?1:0);
