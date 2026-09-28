import {DataUnavailable} from "@/domain/models";
import {AircraftC1Invalid} from "@/domain/aircraft-c1";
import {AircraftC11Invalid} from "@/domain/aircraft-c11";
import {AircraftC2Invalid} from "@/domain/aircraft-c2";
import {AircraftC4Invalid} from "@/domain/aircraft-c4";
import {AircraftC5Invalid} from "@/domain/aircraft-c5";
import {AircraftC7Invalid} from "@/domain/aircraft-c7";
import {AircraftC8Invalid} from "@/domain/aircraft-c8";
import {AircraftD11Invalid} from "@/domain/aircraft-d11";
import {AircraftD2Invalid} from "@/domain/aircraft-d2";
import {AircraftD3Invalid} from "@/domain/aircraft-d3";
import {AircraftD4Invalid} from "@/domain/aircraft-d4";
import {AircraftD5Invalid} from "@/domain/aircraft-d5";
import {AircraftD6Invalid} from "@/domain/aircraft-d6";
import {AircraftD8Invalid} from "@/domain/aircraft-d8";
import {AircraftD9Invalid} from "@/domain/aircraft-d9";
import {AircraftE11Invalid} from "@/domain/aircraft-e11";
import {AircraftE12Invalid} from "@/domain/aircraft-e12";
import {AircraftE2Invalid} from "@/domain/aircraft-e2";
import {AircraftE3Invalid} from "@/domain/aircraft-e3";
import {AircraftE4Invalid} from "@/domain/aircraft-e4";
import {AircraftE5Invalid} from "@/domain/aircraft-e5";
import {AircraftF1Invalid} from "@/domain/aircraft-f1";
import {AircraftG1Invalid} from "@/domain/aircraft-g1";
import {AircraftH1Invalid} from "@/domain/aircraft-h1";
import {BaggageInvalid} from "@/domain/baggage-weights";
import {DetailsInvalid} from "@/domain/carrier-details";
import {CarrierIdentityInvalid} from "@/domain/carrier-onboarding";
import {ClassInvalid} from "@/domain/class-codes";
import {CommodityInvalid} from "@/domain/commodity-codes";
import {CrewInvalid} from "@/domain/crew-weights";
import {DensityInvalid} from "@/domain/density-settings";
import {PassengerInvalid} from "@/domain/passenger-weights";
import {UldInvalid} from "@/domain/uld-specifications";

const prerequisiteErrors=[AircraftC1Invalid,AircraftC11Invalid,AircraftC2Invalid,AircraftC4Invalid,AircraftC5Invalid,AircraftC7Invalid,AircraftC8Invalid,AircraftD11Invalid,AircraftD2Invalid,AircraftD3Invalid,AircraftD4Invalid,AircraftD5Invalid,AircraftD6Invalid,AircraftD8Invalid,AircraftD9Invalid,AircraftE11Invalid,AircraftE12Invalid,AircraftE2Invalid,AircraftE3Invalid,AircraftE4Invalid,AircraftE5Invalid,AircraftF1Invalid,AircraftG1Invalid,AircraftH1Invalid,BaggageInvalid,DetailsInvalid,CarrierIdentityInvalid,ClassInvalid,CommodityInvalid,CrewInvalid,DensityInvalid,PassengerInvalid,UldInvalid];

// A dashboard fans out into many reads. Bound that work and retry only failed reads.
export function createDashboardReader(concurrency=4) {
  let active=0;
  const queue:Array<()=>void>=[];
  async function slot<T>(read:()=>Promise<T>):Promise<T> {
    if(active>=concurrency)await new Promise<void>(resolve=>queue.push(resolve));
    else active++;
    try{return await read();}
    finally{const next=queue.shift();if(next)next();else active--;}
  }
  return async function read<T>(request:()=>Promise<T>):Promise<T|null> {
    return slot(async()=>{
      for(let attempt=0;attempt<2;attempt++){
        try{return await request();}
        catch(error){
          // Existing prerequisite validation (e.g. C1 not yet entered) is incomplete.
          // Infrastructure failures must never be interpreted as missing saved data.
          if(prerequisiteErrors.some(ErrorType=>error instanceof ErrorType))return null;
          if(attempt===1)throw error instanceof Error?error:new DataUnavailable();
        }
      }
      throw new DataUnavailable();
    });
  };
}
