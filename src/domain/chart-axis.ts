export type IntegerAxisScale={min:number;max:number;ticks:number[]};

export function integerAxisScale(rawMin:number,rawMax:number,intervals=4):IntegerAxisScale{
  const count=Math.max(1,Math.trunc(intervals));
  const lower=Math.floor(Math.min(rawMin,rawMax));
  const upper=Math.ceil(Math.max(rawMin,rawMax));
  const step=Math.max(1,Math.ceil(Math.max(1,upper-lower)/count));
  const max=lower+step*count;
  return{min:lower,max,ticks:Array.from({length:count+1},(_,index)=>lower+step*index)};
}
