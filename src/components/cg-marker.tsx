export function CgMarker({x,y,size=14}:{x:number;y:number;size?:number}){
 const radius=size*.38;
 return <g className="cg-marker" aria-hidden="true">
  <circle cx={x} cy={y} r={radius} fill="#ffffff" stroke="#111111" strokeWidth={Math.max(1.8,size*.16)}/>
  <circle cx={x} cy={y} r={Math.max(1,size*.08)} fill="#111111"/>
 </g>;
}
