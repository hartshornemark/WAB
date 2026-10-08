export function CgMarker({x,y,size=14}:{x:number;y:number;size?:number}){
 return <g className="cg-marker" aria-hidden="true">
  <path d={`M ${x-size*.52} ${y-size*.48} L ${x+size*.52} ${y-size*.48} L ${x} ${y+size*.5} Z`} fill="#111111" stroke="#ffffff" strokeWidth={Math.max(1.4,size*.12)} strokeLinejoin="round"/>
 </g>;
}
