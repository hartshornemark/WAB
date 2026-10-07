import "server-only";
import {after} from "next/server";

type AnyService=Record<PropertyKey,unknown>;

const refreshQueues=new Map<string,Promise<void>>();

function enqueueRefresh(iata:string,work:()=>Promise<void>,deduplicate=false){
  const key=iata.trim().toUpperCase();
  const pending=refreshQueues.get(key);
  if(deduplicate&&pending)return pending;
  const task=(pending??Promise.resolve()).catch(()=>undefined).then(work);
  refreshQueues.set(key,task);
  void task.finally(()=>{if(refreshQueues.get(key)===task)refreshQueues.delete(key)});
  return task;
}

const mutationName=(property:PropertyKey)=>typeof property==="string"&&/^(save|import|remove|set)/.test(property);

async function refreshAircraft(iata:string,typeCode:string,subtype:string){
  try{
    const{refreshDashboardStatusSnapshots}=await import("@/composition/dashboard-status-refresh");
    await refreshDashboardStatusSnapshots(iata,[{typeCode,subtype}]);
  }catch(error){console.error("Dashboard status snapshot refresh failed",{iata,typeCode,subtype,errorType:error instanceof Error?error.constructor.name:"Unknown"})}
}

async function refreshCarrier(iata:string){
  try{
    const[{refreshDashboardStatusSnapshots},{carrierHomeServices}]=await Promise.all([
      import("@/composition/dashboard-status-refresh"),
      import("@/composition/services"),
    ]);
    const home=await(await carrierHomeServices()).get(iata);
    for(const aircraft of home.aircraft.rows){
      await refreshDashboardStatusSnapshots(iata,[aircraft]);
    }
  }catch(error){console.error("Carrier dashboard status refresh failed",{iata,errorType:error instanceof Error?error.constructor.name:"Unknown"})}
}

export function scheduleAircraftDashboardStatusRefresh(iata:string,typeCode:string,subtype:string){
  after(()=>enqueueRefresh(iata,()=>refreshAircraft(iata,typeCode,subtype)));
}

export function scheduleCarrierDashboardStatusRefresh(iata:string){
  after(()=>enqueueRefresh(iata,()=>refreshCarrier(iata),true));
}

export function withAircraftDashboardStatusRefresh<T extends AnyService>(service:T):T{
  return new Proxy(service,{
    get(target,property,receiver){
      const value=Reflect.get(target,property,receiver);
      if(typeof value!=="function"||!mutationName(property))return value;
      return async(...args:unknown[])=>{
        const result=await value.apply(target,args);
        const[iata,typeCode,subtype]=args;
        if(typeof iata==="string"&&typeof typeCode==="string"&&typeof subtype==="string")scheduleAircraftDashboardStatusRefresh(iata,typeCode,subtype);
        return result;
      };
    },
  });
}

export function withCarrierDashboardStatusRefresh<T extends AnyService>(service:T):T{
  return new Proxy(service,{
    get(target,property,receiver){
      const value=Reflect.get(target,property,receiver);
      if(typeof value!=="function"||!mutationName(property))return value;
      return async(...args:unknown[])=>{
        const result=await value.apply(target,args);
        if(typeof args[0]==="string")scheduleCarrierDashboardStatusRefresh(args[0]);
        return result;
      };
    },
  });
}
