"use client";

import type { AircraftC4Values } from "@/domain/aircraft-c4";
import type { FuelLoadingSchedule, NonStandardFuelTank } from "@/domain/aircraft-c8";
import {
  calculateFuelScheduleEffect,
  type FuelScheduleEffectPoint,
} from "@/domain/aircraft-c8-schedule-effect";
import { formatNumeric } from "@/domain/display-standards";
import { useIndexDecimalPlaces } from "@/components/index-display-preference";

type ChartPoint = { x: number; y: number; label: string };

function EffectChart({
  title,
  description,
  points,
  xLabel,
  yLabel,
  formatX,
}: {
  title: string;
  description: string;
  points: ChartPoint[];
  xLabel: string;
  yLabel: string;
  formatX: (value: number) => string;
}) {
  const width = 620;
  const height = 330;
  const left = 82;
  const right = 28;
  const top = 28;
  const bottom = 62;
  const plotWidth = width - left - right;
  const plotHeight = height - top - bottom;
  const xValues = points.map((point) => point.x);
  const yValues = points.map((point) => point.y);
  const rawXMin = Math.min(...xValues);
  const rawXMax = Math.max(...xValues);
  const xPadding = Math.max((rawXMax - rawXMin) * 0.08, Math.abs(rawXMax) * 0.04, 0.25);
  const xMin = rawXMin - xPadding;
  const xMax = rawXMax + xPadding;
  const yMax = Math.max(...yValues) * 1.08;
  const x = (value: number) => left + ((value - xMin) / (xMax - xMin)) * plotWidth;
  const y = (value: number) => top + plotHeight - (value / yMax) * plotHeight;
  const ticks = [0, 1, 2, 3, 4];
  const path = points.map((point, index) => `${index === 0 ? "M" : "L"} ${x(point.x)} ${y(point.y)}`).join(" ");

  return <section className="c8-effect-chart">
    <h5>{title}</h5>
    <p>{description}</p>
    <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${title}. ${xLabel} is on the horizontal axis and ${yLabel} is on the vertical axis.`}>
      {ticks.map((tick) => {
        const value = yMax * tick / 4;
        const position = y(value);
        return <g key={`y-${tick}`}><line className="c8-chart-grid" x1={left} x2={width - right} y1={position} y2={position}/><text className="c8-chart-tick" x={left - 12} y={position + 5} textAnchor="end">{Math.ceil(value)}</text></g>;
      })}
      {ticks.map((tick) => {
        const value = xMin + (xMax - xMin) * tick / 4;
        const position = x(value);
        return <g key={`x-${tick}`}><line className="c8-chart-grid" x1={position} x2={position} y1={top} y2={top + plotHeight}/><text className="c8-chart-tick" x={position} y={top + plotHeight + 27} textAnchor="middle">{formatX(value)}</text></g>;
      })}
      <line className="c8-chart-axis" x1={left} x2={left} y1={top} y2={top + plotHeight}/>
      <line className="c8-chart-axis" x1={left} x2={width - right} y1={top + plotHeight} y2={top + plotHeight}/>
      <path className="c8-chart-line" d={path}/>
      {points.map((point) => <g key={point.label}>
        <circle className="c8-effect-point" cx={x(point.x)} cy={y(point.y)} r="6"/>
        <text className="c8-effect-label" x={x(point.x)} y={y(point.y) - 12} textAnchor="middle">{point.label}</text>
      </g>)}
      <text className="c8-chart-axis-label" x={left + plotWidth / 2} y={height - 13} textAnchor="middle">{xLabel}</text>
      <text className="c8-chart-axis-label" x="20" y={top + plotHeight / 2} textAnchor="middle" transform={`rotate(-90 20 ${top + plotHeight / 2})`}>{yLabel}</text>
    </svg>
  </section>;
}

function chartPoints(points: FuelScheduleEffectPoint[], select: (point: FuelScheduleEffectPoint) => number) {
  return points.map((point) => ({ x: select(point), y: point.weight, label: `S${point.step}` }));
}

export function AircraftC8ScheduleEffect({
  schedule,
  tanks,
  formula,
  weightUnit,
  lengthUnit,
}: {
  schedule: FuelLoadingSchedule;
  tanks: NonStandardFuelTank[];
  formula: AircraftC4Values | null;
  weightUnit: string;
  lengthUnit: string;
}) {
  const indexDecimalPlaces = useIndexDecimalPlaces();
  const effect = calculateFuelScheduleEffect(schedule, tanks, formula);
  if (effect.error) return <section className="c8-effect-unavailable"><h5>Fuel Loading Effect</h5><p>{effect.error}</p></section>;

  return <section className="c8-effect-section">
    <div className="c8-effect-heading"><h4>Fuel Loading Effect</h4><p>Cumulative result after each ordered loading step.</p></div>
    <div className="c8-effect-charts">
      <EffectChart title="Fuel Index" description="How the cumulative fuel index changes as fuel is loaded." points={chartPoints(effect.points, (point) => point.indexValue)} xLabel="Index" yLabel={`Fuel Weight (${weightUnit})`} formatX={(value) => formatNumeric(value, "index", indexDecimalPlaces)}/>
      <EffectChart title="Fuel Balance Arm" description="How the cumulative fuel balance arm moves as tanks are loaded." points={chartPoints(effect.points, (point) => point.balanceArm)} xLabel={`Balance Arm (${lengthUnit})`} yLabel={`Fuel Weight (${weightUnit})`} formatX={(value) => value.toFixed(2)}/>
    </div>
    <div className="c8-effect-values" role="table" aria-label="Fuel loading effect values">
      <div className="c8-effect-value c8-head" role="row"><span>Step</span><span>Cumulative Weight ({weightUnit})</span><span>Index</span><span>Balance Arm ({lengthUnit})</span></div>
      {effect.points.map((point) => <div className="c8-effect-value" role="row" key={point.step}><strong>{point.step}</strong><strong>{Math.ceil(point.weight)}</strong><strong>{formatNumeric(point.indexValue, "index", indexDecimalPlaces)}</strong><strong>{point.balanceArm.toFixed(3)}</strong></div>)}
    </div>
  </section>;
}
