import {useState} from "react";
import {useIndexDecimalPlaces} from "@/components/index-display-preference";
import {formatNumeric} from "@/domain/display-standards";
import {conditionalEnvelopes,envelopeMode,type AircraftC5Values,type EnvelopeBoundary,type EnvelopePoint} from "@/domain/aircraft-c5";
import type { AircraftC4Values } from "@/domain/aircraft-c4";
import type { AircraftC5Applicability } from "@/domain/aircraft-c2-status";
import {trimAircraftC7LineToMaximum,type AircraftC7PlottedPoint,type AircraftC7Point} from "@/domain/aircraft-c7";
import { indexForMacPercent, macPercentForIndex } from "@/domain/aircraft-balance-formula";

type Phase = "tow" | "law" | "zfw";
type SharedScale = { xMin: number; xMax: number; yMin: number; yMax: number };
type PlottedPoint = AircraftC7PlottedPoint;

const charts: { key: Phase; title: string }[] = [
  { key: "zfw", title: "Zero Fuel Balance Envelope" },
  { key: "tow", title: "Take-Off Balance Envelope" },
  { key: "law", title: "Landing Balance Envelope" },
];

const WIDTH = 560;
const HEIGHT = 390;
const plot = { left: 72, right: 24, top: 58, bottom: 64 };
const plotWidth = WIDTH - plot.left - plot.right;
const plotHeight = HEIGHT - plot.top - plot.bottom;

const sorted = (rows: EnvelopePoint[]) => [...rows].sort((a, b) => a.weight - b.weight);
const niceStep = (range: number) => {
  const rough = range / 5;
  const magnitude = 10 ** Math.floor(Math.log10(rough));
  const normalised = rough / magnitude;
  const factor = normalised <= 1 ? 1 : normalised <= 2 ? 2 : normalised <= 5 ? 5 : 10;
  return factor * magnitude;
};
const rangeTicks = (minimum: number, maximum: number, step: number) => {
  const values = [minimum];
  for (let value = Math.ceil(minimum / step) * step; value < maximum; value += step) {
    if (value - minimum >= step * 0.35 && maximum - value >= step * 0.35) values.push(value);
  }
  if (maximum !== minimum) values.push(maximum);
  return values;
};
const sharedScale = (boundaries:EnvelopeBoundary[], idealTrim: PlottedPoint[]): SharedScale => {
  const all = [...boundaries.flatMap(boundary=>[...boundary.fwd,...boundary.aft]), ...idealTrim];
  const rawXMin = Math.min(...all.map((point) => point.indexValue));
  const rawXMax = Math.max(...all.map((point) => point.indexValue));
  const xPadding = Math.max((rawXMax - rawXMin) * 0.1, 1);
  return {
    xMin: Math.floor((rawXMin - xPadding) / 10) * 10,
    xMax: Math.ceil((rawXMax + xPadding) / 10) * 10,
    yMin: Math.min(...all.map((point) => point.weight)),
    yMax: Math.max(...all.map((point) => point.weight)),
  };
};
const macTicks = (scale: SharedScale, formula: AircraftC4Values) => {
  const first = Math.ceil(macPercentForIndex(scale.yMax, scale.xMin, formula));
  const last = Math.floor(macPercentForIndex(scale.yMax, scale.xMax, formula));
  return Array.from({ length: Math.max(0, last - first + 1) }, (_, index) => first + index);
};

function EnvelopeSvg({ boundary, title, unit, scale, formula, idealTrim }: { boundary: EnvelopeBoundary; title: string; unit: string; scale: SharedScale; formula: AircraftC4Values | null; idealTrim: PlottedPoint[] }) {
  const indexDecimalPlaces=useIndexDecimalPlaces();
  const fwd = sorted(boundary.fwd);
  const aft = sorted(boundary.aft);
  const { xMin, xMax, yMin, yMax } = scale;
  const x = (value: number) => plot.left + ((value - xMin) / (xMax - xMin)) * plotWidth;
  const y = (value: number) => plot.top + plotHeight - ((value - yMin) / (yMax - yMin)) * plotHeight;
  const points = (rows: PlottedPoint[]) => rows.map((point) => `${x(point.indexValue)},${y(point.weight)}`).join(" ");
  const polygon = points([...fwd, ...[...aft].reverse()]);
  const xTicks = rangeTicks(xMin, xMax, 10);
  const yTicks = rangeTicks(yMin, yMax, niceStep(yMax - yMin));
  const macValues = formula ? macTicks(scale, formula) : [];
  const clipId = `mac-${title.toLowerCase().replace(/[^a-z]+/g,"-")}`;
  const maximumWeight=Math.max(...fwd.map(point=>point.weight),...aft.map(point=>point.weight));
  const boundedIdealTrim=trimAircraftC7LineToMaximum(idealTrim,maximumWeight);

  return <figure className="c5-envelope-chart">
    <figcaption>{title}</figcaption>
    <svg viewBox={`0 0 ${WIDTH} ${HEIGHT}`} role="img" aria-label={`${title}: Index against Weight in ${unit}`}>
      <title>{title}</title>
      <desc>The shaded area between the Forward and Aft limits is the permitted balance envelope.</desc>
      <defs><clipPath id={clipId}><rect x={plot.left} y={plot.top} width={plotWidth} height={plotHeight} /></clipPath></defs>
      <rect x={plot.left} y={plot.top} width={plotWidth} height={plotHeight} className="envelope-plot-background" />
      {yTicks.map((value) => <g key={`y-${value}`}>
        <line x1={plot.left} y1={y(value)} x2={WIDTH - plot.right} y2={y(value)} className="envelope-grid-line" />
        <text x={plot.left - 10} y={y(value) + 4} textAnchor="end" className="envelope-axis-tick">{Math.round(value).toLocaleString()}</text>
      </g>)}
      {xTicks.map((value) => <g key={`x-${value}`}>
        <line x1={x(value)} y1={plot.top} x2={x(value)} y2={HEIGHT - plot.bottom} className="envelope-grid-line" />
        <text x={x(value)} y={HEIGHT - plot.bottom + 22} textAnchor="middle" className="envelope-axis-tick">{formatNumeric(value,"index",indexDecimalPlaces)}</text>
      </g>)}
      <polygon points={polygon} className="envelope-valid-area" />
      {formula&&<g><g clipPath={`url(#${clipId})`}>{macValues.map(value=><line key={`mac-line-${value}`} x1={x(indexForMacPercent(yMin,value,formula))} y1={y(yMin)} x2={x(indexForMacPercent(yMax,value,formula))} y2={y(yMax)} className={`envelope-mac-line ${value%5===0?"major":"minor"}`} />)}</g><line x1={plot.left} y1={plot.top} x2={WIDTH-plot.right} y2={plot.top} className="envelope-mac-axis" /><text x={plot.left+plotWidth/2} y="14" textAnchor="middle" className="envelope-mac-label">% MAC</text>{macValues.map(value=><line key={`mac-top-tick-${value}`} x1={x(indexForMacPercent(yMax,value,formula))} y1={plot.top} x2={x(indexForMacPercent(yMax,value,formula))} y2={plot.top-(value%5===0?7:4)} className="envelope-mac-axis" />)}{macValues.filter(value=>value%5===0).map(value=><text key={`mac-label-${value}`} x={x(indexForMacPercent(yMax,value,formula))} y={plot.top-9} textAnchor="middle" className="envelope-mac-tick">{value}</text>)}</g>}
      <polyline points={points(fwd)} className="envelope-limit-line envelope-fwd-line" />
      <polyline points={points(aft)} className="envelope-limit-line envelope-aft-line" />
      {boundedIdealTrim.length>=2&&<polyline points={points(boundedIdealTrim)} className="envelope-ideal-trim-line" clipPath={`url(#${clipId})`} />}
      <line x1={plot.left} y1={HEIGHT - plot.bottom} x2={WIDTH - plot.right} y2={HEIGHT - plot.bottom} className="envelope-axis-line" />
      <line x1={plot.left} y1={plot.top} x2={plot.left} y2={HEIGHT - plot.bottom} className="envelope-axis-line" />
      <text x={plot.left + plotWidth / 2} y={HEIGHT - 12} textAnchor="middle" className="envelope-axis-label">Index</text>
      <text transform={`translate(18 ${plot.top + plotHeight / 2}) rotate(-90)`} textAnchor="middle" className="envelope-axis-label">Weight ({unit})</text>
    </svg>
    <div className="c5-envelope-legend" aria-hidden="true"><span><i className="fwd" />FWD Limit</span><span><i className="aft" />AFT Limit</span><span><i className="area" />Permitted Envelope</span>{boundedIdealTrim.length>=2&&<span><i className="ideal-trim" />Ideal Trim</span>}</div>
  </figure>;
}

type CombinedSeries={key:string;label:string;className:string;boundary:EnvelopeBoundary};
function CombinedEnvelopeSvg({ unit, scale, formula, series, idealTrim }: { unit: string; scale: SharedScale; formula: AircraftC4Values | null; series:CombinedSeries[]; idealTrim: PlottedPoint[] }) {
  const indexDecimalPlaces=useIndexDecimalPlaces();
  const width = 920, height = 500;
  const margin = { left: 82, right: 30, top: 58, bottom: 70 };
  const innerWidth = width - margin.left - margin.right;
  const innerHeight = height - margin.top - margin.bottom;
  const combinedLabel=series.map(item=>item.label).join(", ");
  const { xMin, xMax, yMin, yMax } = scale;
  const x = (value: number) => margin.left + ((value - xMin) / (xMax - xMin)) * innerWidth;
  const y = (value: number) => margin.top + innerHeight - ((value - yMin) / (yMax - yMin)) * innerHeight;
  const points = (rows: PlottedPoint[]) => rows.map((point) => `${x(point.indexValue)},${y(point.weight)}`).join(" ");
  const polygon = (boundary: EnvelopeBoundary) => points([...sorted(boundary.fwd), ...sorted(boundary.aft).reverse()]);
  const xTicks = rangeTicks(xMin, xMax, 10);
  const yTicks = rangeTicks(yMin, yMax, niceStep(yMax - yMin));
  const macValues = formula ? macTicks(scale, formula) : [];

  return <figure className="c5-envelope-chart c5-combined-envelope-chart">
    <figcaption>Combined Balance Envelope — {combinedLabel}</figcaption>
    <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`Combined ${combinedLabel} balance envelopes: Index against Weight in ${unit}`}>
      <title>Combined Balance Envelope — {combinedLabel}</title>
      <desc>The required permitted balance envelopes are overlaid on one shared Index and Weight scale.</desc>
      <defs><clipPath id="combined-mac-grid"><rect x={margin.left} y={margin.top} width={innerWidth} height={innerHeight} /></clipPath></defs>
      <rect x={margin.left} y={margin.top} width={innerWidth} height={innerHeight} className="envelope-plot-background" />
      {yTicks.map((value) => <g key={`combined-y-${value}`}><line x1={margin.left} y1={y(value)} x2={width - margin.right} y2={y(value)} className="envelope-grid-line" /><text x={margin.left - 12} y={y(value) + 4} textAnchor="end" className="envelope-axis-tick">{Math.round(value).toLocaleString()}</text></g>)}
      {xTicks.map((value) => <g key={`combined-x-${value}`}><line x1={x(value)} y1={margin.top} x2={x(value)} y2={height - margin.bottom} className="envelope-grid-line" /><text x={x(value)} y={height - margin.bottom + 24} textAnchor="middle" className="envelope-axis-tick">{formatNumeric(value,"index",indexDecimalPlaces)}</text></g>)}
      {series.map(({ key, className, boundary }) => <polygon key={key} points={polygon(boundary)} className={`combined-envelope-area ${className}`} />)}
      {idealTrim.length>=2&&<polyline points={points(idealTrim)} className="envelope-ideal-trim-line" clipPath="url(#combined-mac-grid)" />}
      {formula&&<g><g clipPath="url(#combined-mac-grid)">{macValues.map(value=><line key={`combined-mac-line-${value}`} x1={x(indexForMacPercent(yMin,value,formula))} y1={y(yMin)} x2={x(indexForMacPercent(yMax,value,formula))} y2={y(yMax)} className={`envelope-mac-line ${value%5===0?"major":"minor"}`} />)}</g><line x1={margin.left} y1={margin.top} x2={width-margin.right} y2={margin.top} className="envelope-mac-axis" /><text x={margin.left+innerWidth/2} y="15" textAnchor="middle" className="envelope-mac-label">% MAC</text>{macValues.map(value=><line key={`combined-mac-top-tick-${value}`} x1={x(indexForMacPercent(yMax,value,formula))} y1={margin.top} x2={x(indexForMacPercent(yMax,value,formula))} y2={margin.top-(value%5===0?8:4)} className="envelope-mac-axis" />)}{macValues.filter(value=>value%5===0).map(value=><text key={`combined-mac-label-${value}`} x={x(indexForMacPercent(yMax,value,formula))} y={margin.top-10} textAnchor="middle" className="envelope-mac-tick">{value}</text>)}</g>}
      <line x1={margin.left} y1={height - margin.bottom} x2={width - margin.right} y2={height - margin.bottom} className="envelope-axis-line" />
      <line x1={margin.left} y1={margin.top} x2={margin.left} y2={height - margin.bottom} className="envelope-axis-line" />
      <text x={margin.left + innerWidth / 2} y={height - 14} textAnchor="middle" className="envelope-axis-label">Index</text>
      <text transform={`translate(20 ${margin.top + innerHeight / 2}) rotate(-90)`} textAnchor="middle" className="envelope-axis-label">Weight ({unit})</text>
    </svg>
    <div className="c5-envelope-legend combined" aria-hidden="true">{series.map(({ key, label, className }) => <span key={key}><i className={className} />{label}</span>)}{idealTrim.length>=2&&<span><i className="ideal-trim" />Ideal Trim</span>}</div>
  </figure>;
}

export function BalanceEnvelopeView({ values, applicability, unit, formula, idealTrimPoints=[], onClose }: { values: AircraftC5Values; applicability:AircraftC5Applicability; unit: string; formula: AircraftC4Values | null; idealTrimPoints?: AircraftC7Point[]; onClose: () => void }) {
  const activeCharts=charts.filter(chart=>applicability[chart.key]);
  const chartInstances=activeCharts.flatMap(chart=>envelopeMode(values,chart.key)==="CONDITIONAL"?conditionalEnvelopes(values,chart.key).map(item=>({key:`${chart.key}-${item.id}`,phase:chart.key,title:`${chart.title} — ${item.code}`,boundary:item.boundary,condition:item.conditionBasis==="OTHER"?item.conditionDescription:`${item.conditionBasis==="TAKE_OFF_FUEL"?"Take-off fuel":"Landing fuel"}: ${item.lowerBound===null?"":`${item.lowerInclusive?"≥":">"} ${item.lowerBound.toLocaleString()} ${unit}`} ${item.upperBound===null?"":`${item.upperInclusive?"≤":"<"} ${item.upperBound.toLocaleString()} ${unit}`}`.trim()})):[{key:chart.key,phase:chart.key,title:chart.title,boundary:values.envelopes[chart.key],condition:""}]);
  const conditionalGroups=activeCharts.flatMap(chart=>{const options=chartInstances.filter(item=>item.phase===chart.key&&item.condition);return options.length?[{phase:chart.key,label:`${chart.key.toUpperCase()} CONDITION`,options}]:[]});
  const[selectedConditions,setSelectedConditions]=useState<Record<string,string>>(()=>Object.fromEntries(conditionalGroups.map(group=>[group.phase,group.options[0].key])));
  const overlayInstances=chartInstances.filter(chart=>!chart.condition||selectedConditions[chart.phase]===chart.key);
  const idealTrim=idealTrimPoints.map(point=>({weight:point.weight,indexValue:point.indexValue??(formula&&point.macValue!==null?indexForMacPercent(point.weight,point.macValue,formula):Number.NaN)})).filter(point=>Number.isFinite(point.weight)&&Number.isFinite(point.indexValue)).sort((a,b)=>a.weight-b.weight);
  const scale = sharedScale(chartInstances.map(item=>item.boundary),idealTrim);
  const combinedSeries:CombinedSeries[]=overlayInstances
    .slice()
    .sort((a,b)=>Math.max(...b.boundary.fwd.map(point=>point.weight),...b.boundary.aft.map(point=>point.weight))-Math.max(...a.boundary.fwd.map(point=>point.weight),...a.boundary.aft.map(point=>point.weight)))
    .map((chart,index)=>({key:chart.key,label:chart.title.replace(" Balance Envelope",""),className:`combined-series-${index%8}`,boundary:chart.boundary}));
  return <section className="c5-envelope-view" aria-labelledby="balance-envelope-view-heading">
    <div className="c5-envelope-view-heading"><div><h3 id="balance-envelope-view-heading">AHM565 Sheet C5.2 — Balance Envelope</h3><p>Automatically generated from the configured C5.1 Forward and Aft limits.{formula?" Dashed guides show calculated constant % MAC.":""}{idealTrim.length>=2?" The Ideal Trim line is overlaid from C7.":""}</p></div><button type="button" className="secondary" onClick={onClose}>CLOSE</button></div>
    {conditionalGroups.map(group=><nav className="c5-envelope-condition-selectors" aria-label={`${group.label} overlay`} key={group.phase}><span>{group.label}</span>{group.options.map(option=><button type="button" className={selectedConditions[group.phase]===option.key?"selected":""} aria-pressed={selectedConditions[group.phase]===option.key} key={option.key} onClick={()=>setSelectedConditions(current=>({...current,[group.phase]:option.key}))}>{option.title.split(" — ").at(-1)}</button>)}</nav>)}
    <div className="c5-envelope-charts">{chartInstances.length>1&&<CombinedEnvelopeSvg unit={unit} scale={scale} formula={formula} series={combinedSeries} idealTrim={idealTrim}/>} {chartInstances.map((chart) => <div key={chart.key}>{chart.condition&&<p className="c5-chart-condition">{chart.condition}</p>}<EnvelopeSvg boundary={chart.boundary} title={chart.title} unit={unit} scale={scale} formula={formula} idealTrim={idealTrim} /></div>)}</div>
  </section>;
}
