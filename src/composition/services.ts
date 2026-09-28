import "server-only";
import {createDashboardReader} from "@/application/dashboard-read";
import { createCarrierConfiguration } from "@/application/carrier-configuration";
import { createRequestClient } from "@/infrastructure/supabase/server";
import { createAuthAdapter } from "@/infrastructure/supabase/auth-adapter";
import { createCarrierAdapter } from "@/infrastructure/supabase/carrier-adapter";
import {createCarrierAdministration}from"@/application/carrier-administration";
import {createCarrierAdministrationAdapter}from"@/infrastructure/supabase/carrier-administration-adapter";
import {AuthenticationRequired,CarrierUnavailable}from"@/domain/models";
import { createLogoAdapter } from "@/infrastructure/supabase/logo-adapter";
import { logoImageProcessor } from "@/infrastructure/images/logo-image-processor";
import { createCarrierLogos } from "@/application/carrier-logos";
// The only composition root: new adapters/client for every request; no shared session state.
export async function services() {
  const client = await createRequestClient();
  return createCarrierConfiguration(createAuthAdapter(client), createCarrierAdapter(client), createLogoAdapter(client));
}

export async function carrierAdministrationServices(){const client=await createRequestClient();return createCarrierAdministration(createAuthAdapter(client),createCarrierAdministrationAdapter(client));}

export async function logoServices() {
  const client = await createRequestClient();
  return createCarrierLogos(createAuthAdapter(client), createCarrierAdapter(client), createLogoAdapter(client), logoImageProcessor);
}

import { createCarrierDetails } from "@/application/carrier-details";
import { createDetailsAdapter } from "@/infrastructure/supabase/details-adapter";
export async function detailsServices() {
  const client = await createRequestClient();
  return createCarrierDetails(createAuthAdapter(client), createCarrierAdapter(client), createDetailsAdapter(client));
}

import { createCommodityCodes } from "@/application/commodity-codes";
import { createCommodityAdapter } from "@/infrastructure/supabase/commodity-adapter";
export async function commodityServices() {
  const client = await createRequestClient();
  return createCommodityCodes(createAuthAdapter(client), createCarrierAdapter(client), createCommodityAdapter(client));
}

import { createClassCodes } from "@/application/class-codes";
import { createClassAdapter } from "@/infrastructure/supabase/class-adapter";
export async function classServices() {
  const client = await createRequestClient();
  return createClassCodes(createAuthAdapter(client), createCarrierAdapter(client), createClassAdapter(client));
}

import { createCrewWeights } from "@/application/crew-weights";
import { createCrewAdapter } from "@/infrastructure/supabase/crew-adapter";
export async function crewServices() {
  const client = await createRequestClient();
  return createCrewWeights(createAuthAdapter(client), createCarrierAdapter(client), createCrewAdapter(client));
}

import { createPassengerWeights } from "@/application/passenger-weights";
import { createPassengerAdapter } from "@/infrastructure/supabase/passenger-adapter";
export async function passengerServices() {
  const client = await createRequestClient();
  return createPassengerWeights(createAuthAdapter(client),createCarrierAdapter(client),createPassengerAdapter(client));
}

import { createBaggageWeights } from "@/application/baggage-weights";
import { createBaggageAdapter } from "@/infrastructure/supabase/baggage-adapter";
export async function baggageServices(){const client=await createRequestClient();return createBaggageWeights(createAuthAdapter(client),createCarrierAdapter(client),createBaggageAdapter(client));}

import {createDensitySettings} from "@/application/density-settings";
import {createDensityAdapter} from "@/infrastructure/supabase/density-adapter";
export async function densityServices(){const client=await createRequestClient();return createDensitySettings(createAuthAdapter(client),createCarrierAdapter(client),createDensityAdapter(client));}

import {createUldSpecifications} from "@/application/uld-specifications";
import {createUldAdapter} from "@/infrastructure/supabase/uld-adapter";
export async function uldServices(){const client=await createRequestClient();return createUldSpecifications(createAuthAdapter(client),createCarrierAdapter(client),createUldAdapter(client));}

import {createAircraftC1} from "@/application/aircraft-c1";
import {createAircraftC1Adapter} from "@/infrastructure/supabase/aircraft-c1-adapter";
export async function aircraftC1Services(){const client=await createRequestClient();return createAircraftC1(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC1Adapter(client));}
import{createCarrierHome}from"@/application/carrier-home";
export async function carrierHomeServices(){const client=await createRequestClient();return createCarrierHome(createAuthAdapter(client),createCarrierAdapter(client),createLogoAdapter(client),createAircraftC1Adapter(client));}

import {createAircraftC2} from "@/application/aircraft-c2";
import {createAircraftC2Adapter} from "@/infrastructure/supabase/aircraft-c2-adapter";
export async function aircraftC2Services(){const client=await createRequestClient();return createAircraftC2(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC2Adapter(client));}

import {createAircraftC4} from "@/application/aircraft-c4";
import {createAircraftC4Adapter} from "@/infrastructure/supabase/aircraft-c4-adapter";
export async function aircraftC4Services(){const client=await createRequestClient();return createAircraftC4(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC4Adapter(client));}

import {createAircraftC5} from "@/application/aircraft-c5";
import {createAircraftC5Adapter} from "@/infrastructure/supabase/aircraft-c5-adapter";
export async function aircraftC5Services(){const client=await createRequestClient();return createAircraftC5(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC5Adapter(client));}

import {createAircraftC7} from "@/application/aircraft-c7";
import {createAircraftC7Adapter} from "@/infrastructure/supabase/aircraft-c7-adapter";
export async function aircraftC7Services(){const client=await createRequestClient();return createAircraftC7(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC7Adapter(client));}
import {createAircraftC8} from "@/application/aircraft-c8";
import {createAircraftC8Adapter} from "@/infrastructure/supabase/aircraft-c8-adapter";
export async function aircraftC8Services(){const client=await createRequestClient();return createAircraftC8(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC8Adapter(client));}
import{createAircraftC11}from"@/application/aircraft-c11";import{createAircraftC11Adapter}from"@/infrastructure/supabase/aircraft-c11-adapter";
export async function aircraftC11Services(){const client=await createRequestClient();return createAircraftC11(createAuthAdapter(client),createCarrierAdapter(client),createAircraftC11Adapter(client));}
import{createAircraftD2}from"@/application/aircraft-d2";import{createAircraftD2Adapter}from"@/infrastructure/supabase/aircraft-d2-adapter";
export async function aircraftD2Services(){const client=await createRequestClient();return createAircraftD2(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD2Adapter(client),createAircraftC4Adapter(client));}
import{createAircraftD3}from"@/application/aircraft-d3";import{createAircraftD3Adapter}from"@/infrastructure/supabase/aircraft-d3-adapter";
export async function aircraftD3Services(){const client=await createRequestClient();return createAircraftD3(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD3Adapter(client),createAircraftC4Adapter(client));}
import{createAircraftD4}from"@/application/aircraft-d4";import{createAircraftD4Adapter}from"@/infrastructure/supabase/aircraft-d4-adapter";
export async function aircraftD4Services(){const client=await createRequestClient();return createAircraftD4(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD4Adapter(client));}
import{createAircraftD5}from"@/application/aircraft-d5";import{createAircraftD5Adapter}from"@/infrastructure/supabase/aircraft-d5-adapter";
export async function aircraftD5Services(){const client=await createRequestClient();return createAircraftD5(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD5Adapter(client),createAircraftC4Adapter(client));}
import{createAircraftD6}from"@/application/aircraft-d6";import{createAircraftD6Adapter}from"@/infrastructure/supabase/aircraft-d6-adapter";
export async function aircraftD6Services(){const client=await createRequestClient();return createAircraftD6(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD6Adapter(client),createAircraftC4Adapter(client));}
import{createAircraftD8}from"@/application/aircraft-d8";import{createAircraftD8Adapter}from"@/infrastructure/supabase/aircraft-d8-adapter";
export async function aircraftD8Services(){const client=await createRequestClient();return createAircraftD8(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD8Adapter(client),createAircraftC4Adapter(client));}
import{createAircraftD9}from"@/application/aircraft-d9";import{createAircraftD9Adapter}from"@/infrastructure/supabase/aircraft-d9-adapter";
export async function aircraftD9Services(){const client=await createRequestClient();return createAircraftD9(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD9Adapter(client),createAircraftC4Adapter(client));}
import{createAircraftD11}from"@/application/aircraft-d11";import{createAircraftD11Adapter}from"@/infrastructure/supabase/aircraft-d11-adapter";
export async function aircraftD11Services(){const client=await createRequestClient();return createAircraftD11(createAuthAdapter(client),createCarrierAdapter(client),createAircraftD11Adapter(client));}
import{createAircraftE11}from"@/application/aircraft-e11";import{createAircraftE11Adapter}from"@/infrastructure/supabase/aircraft-e11-adapter";
export async function aircraftE11Services(){const client=await createRequestClient();return createAircraftE11(createAuthAdapter(client),createCarrierAdapter(client),createAircraftE11Adapter(client));}
import{createAircraftE12}from"@/application/aircraft-e12";import{createAircraftE12Adapter}from"@/infrastructure/supabase/aircraft-e12-adapter";
export async function aircraftE12Services(){const client=await createRequestClient();return createAircraftE12(createAuthAdapter(client),createCarrierAdapter(client),createAircraftE12Adapter(client));}

import {createAircraftE2} from "@/application/aircraft-e2";
import {createAircraftE2Adapter} from "@/infrastructure/supabase/aircraft-e2-adapter";
export async function aircraftE2Services(){const client=await createRequestClient();return createAircraftE2(createAuthAdapter(client),createCarrierAdapter(client),createAircraftE2Adapter(client));}
import {createAircraftE3} from "@/application/aircraft-e3";
import {createAircraftE3Adapter} from "@/infrastructure/supabase/aircraft-e3-adapter";
export async function aircraftE3Services(){const client=await createRequestClient();return createAircraftE3(createAuthAdapter(client),createCarrierAdapter(client),createAircraftE3Adapter(client));}
import {createAircraftE4} from "@/application/aircraft-e4";
import {createAircraftE4Adapter} from "@/infrastructure/supabase/aircraft-e4-adapter";
export async function aircraftE4Services(){const client=await createRequestClient();return createAircraftE4(createAuthAdapter(client),createCarrierAdapter(client),createAircraftE4Adapter(client));}
import {createAircraftE5} from "@/application/aircraft-e5";
import {createAircraftE5Adapter} from "@/infrastructure/supabase/aircraft-e5-adapter";
export async function aircraftE5Services(){const client=await createRequestClient();return createAircraftE5(createAuthAdapter(client),createCarrierAdapter(client),createAircraftE5Adapter(client));}
import {createAircraftF1} from "@/application/aircraft-f1";
import {createAircraftF1Adapter} from "@/infrastructure/supabase/aircraft-f1-adapter";
export async function aircraftF1Services(){const client=await createRequestClient();return createAircraftF1(createAuthAdapter(client),createCarrierAdapter(client),createAircraftF1Adapter(client));}
import {createAircraftG1} from "@/application/aircraft-g1";
import {createAircraftG1Adapter} from "@/infrastructure/supabase/aircraft-g1-adapter";
export async function aircraftG1Services(){const client=await createRequestClient();return createAircraftG1(createAuthAdapter(client),createCarrierAdapter(client),createAircraftG1Adapter(client));}
import {createAircraftH1} from "@/application/aircraft-h1";
import {createAircraftH1Adapter} from "@/infrastructure/supabase/aircraft-h1-adapter";
export async function aircraftH1Services(){const client=await createRequestClient();return createAircraftH1(createAuthAdapter(client),createCarrierAdapter(client),createAircraftH1Adapter(client));}

// Dashboard reads share one request client and perform the access check once.
// This prevents a dashboard refresh from opening dozens of independent auth checks.
export async function dashboardStatusServices(){
  const client=await createRequestClient(),auth=createAuthAdapter(client),carriers=createCarrierAdapter(client);
  const repositories=[
    createDetailsAdapter(client),createDensityAdapter(client),createClassAdapter(client),createCommodityAdapter(client),createCrewAdapter(client),createPassengerAdapter(client),createBaggageAdapter(client),createUldAdapter(client),
    createAircraftC1Adapter(client),createAircraftC2Adapter(client),createAircraftC4Adapter(client),createAircraftC5Adapter(client),createAircraftC7Adapter(client),createAircraftC8Adapter(client),createAircraftC11Adapter(client),
    createAircraftD2Adapter(client),createAircraftD3Adapter(client),createAircraftD4Adapter(client),createAircraftD5Adapter(client),createAircraftD6Adapter(client),createAircraftD8Adapter(client),createAircraftD9Adapter(client),createAircraftD11Adapter(client),
    createAircraftE11Adapter(client),createAircraftE12Adapter(client),createAircraftE2Adapter(client),createAircraftE3Adapter(client),createAircraftE4Adapter(client),createAircraftE5Adapter(client),createAircraftF1Adapter(client),createAircraftG1Adapter(client),createAircraftH1Adapter(client),
  ] as const;
  const safe=createDashboardReader(4);
  const commonReads=(iata:string)=>Promise.all([
    safe(()=>repositories[0].get(iata)),safe(()=>repositories[1].get(iata)),safe(()=>repositories[2].get(iata)),safe(()=>repositories[3].get(iata)),safe(()=>repositories[4].get(iata)),safe(()=>repositories[5].get(iata)),safe(()=>repositories[6].get(iata)),
  ]);
  const aircraftReads=(iata:string,typeCode:string,subtype:string)=>Promise.all([
    safe(()=>repositories[8].get(iata,typeCode,subtype)),safe(()=>repositories[9].get(iata,typeCode,subtype)),safe(()=>repositories[10].get(iata,typeCode,subtype)),safe(()=>repositories[11].get(iata,typeCode,subtype)),safe(()=>repositories[12].get(iata,typeCode,subtype)),safe(()=>repositories[13].get(iata,typeCode,subtype)),safe(()=>repositories[14].get(iata,typeCode,subtype)),
    safe(()=>repositories[15].get(iata,typeCode,subtype)),safe(()=>repositories[16].get(iata,typeCode,subtype)),safe(()=>repositories[17].get(iata,typeCode,subtype)),safe(()=>repositories[18].get(iata,typeCode,subtype)),safe(()=>repositories[19].get(iata,typeCode,subtype)),safe(()=>repositories[20].get(iata,typeCode,subtype)),safe(()=>repositories[21].get(iata,typeCode,subtype)),safe(()=>repositories[22].get(iata,typeCode,subtype)),
    safe(()=>repositories[23].get(iata,typeCode,subtype)),safe(()=>repositories[24].get(iata,typeCode,subtype)),safe(()=>repositories[25].get(iata,typeCode,subtype)),safe(()=>repositories[26].get(iata,typeCode,subtype)),safe(()=>repositories[27].get(iata,typeCode,subtype)),safe(()=>repositories[28].get(iata,typeCode,subtype)),safe(()=>repositories[29].get(iata,typeCode,subtype)),safe(()=>repositories[30].get(iata,typeCode,subtype)),safe(()=>repositories[31].get(iata,typeCode,subtype)),
  ]);
  const requireAccess=async(iata:string)=>{
    if(!await auth.currentUser())throw new AuthenticationRequired();
    if(!await carriers.findAuthorised(iata))throw new CarrierUnavailable();
  };
  return{async getCarrier(iata:string){
    await requireAccess(iata);
    return Promise.all([
      safe(()=>repositories[0].get(iata)),safe(()=>repositories[1].get(iata)),safe(()=>repositories[2].get(iata)),safe(()=>repositories[3].get(iata)),safe(()=>repositories[4].get(iata)),safe(()=>repositories[5].get(iata)),safe(()=>repositories[6].get(iata)),safe(()=>repositories[8].list(iata)),
    ]);
  },async get(iata:string,typeCode:string,subtype:string){
    await requireAccess(iata);
    const[common,uld,aircraft]=await Promise.all([commonReads(iata),safe(()=>repositories[7].get(iata,typeCode,subtype)),aircraftReads(iata,typeCode,subtype)]);
    return[...common,uld,...aircraft] as const;
  },async getMany(iata:string,variants:Array<{typeCode:string;subtype:string}>){
    await requireAccess(iata);
    const common=await commonReads(iata);
    return Promise.all(variants.map(async variant=>{
      try {
        const [uld,aircraft]=await Promise.all([
          safe(()=>repositories[7].get(iata,variant.typeCode,variant.subtype)),
          aircraftReads(iata,variant.typeCode,variant.subtype),
        ]);
        return [...common,uld,...aircraft] as const;
      } catch(error) {
        console.error("Aircraft status read unavailable",{iata,typeCode:variant.typeCode,subtype:variant.subtype,errorType:error instanceof Error?error.constructor.name:"Unknown"});
        return null;
      }
    }));
  }};
}

import {createAircraftLayouts} from "@/application/aircraft-layouts";
import {createAircraftLayoutAdapter} from "@/infrastructure/supabase/aircraft-layouts";
export async function aircraftLayoutServices(){const client=await createRequestClient();return createAircraftLayouts(createAuthAdapter(client),createAircraftLayoutAdapter(client));}
