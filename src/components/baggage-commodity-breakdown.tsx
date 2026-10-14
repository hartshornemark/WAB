import{baggageCommodityAllocations}from"@/domain/baggage-commodities";

type BaggageRow={classCode?:string|null;commodityCode?:unknown;commodities?:unknown;pieces:unknown;netWeight:unknown};

export function BaggageCommodityBreakdown({row}:{row:BaggageRow}){
 const allocations=baggageCommodityAllocations(row).filter(allocation=>allocation.pieces>0||allocation.netWeight>0);
 if(!allocations.length)return null;
 return <span className="baggage-commodity-breakdown" aria-label={`Baggage by class: ${allocations.map(allocation=>`${allocation.commodityCode} ${allocation.pieces} pieces`).join(", ")}`}><small>BAGGAGE BY CLASS</small><span className="baggage-commodity-chips">{allocations.map(allocation=><span className="baggage-commodity-chip" key={allocation.commodityCode}><b>{allocation.commodityCode}</b><span>{allocation.pieces} PCS</span></span>)}</span></span>
}
