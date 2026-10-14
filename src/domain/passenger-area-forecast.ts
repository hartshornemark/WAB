export type PassengerAreaCapacity={areaId:string;seats:number};
export type PassengerAreaForecast=PassengerAreaCapacity&{passengers:number};

export function forecastPassengerAreas(totalPassengers:number,areas:PassengerAreaCapacity[]):PassengerAreaForecast[]{
 const usable=areas.filter(area=>area.seats>0),totalSeats=usable.reduce((sum,area)=>sum+area.seats,0);
 if(!usable.length||totalSeats<=0)return[];
 const planned=Math.max(0,Math.min(Math.trunc(totalPassengers),totalSeats));
 const shares=usable.map((area,index)=>{const exact=planned*area.seats/totalSeats,count=Math.floor(exact);return{...area,index,count,fraction:exact-count}});
 let remaining=planned-shares.reduce((sum,area)=>sum+area.count,0);
 for(const area of [...shares].sort((left,right)=>right.fraction-left.fraction||left.index-right.index)){if(remaining<=0)break;area.count++;remaining--;}
 return shares.sort((left,right)=>left.index-right.index).map(({areaId,seats,count})=>({areaId,seats,passengers:count}));
}
