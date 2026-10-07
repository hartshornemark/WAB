import test from"node:test";
import assert from"node:assert/strict";
import{parseSsimChapter7}from"../src/domain/ssim-chapter7";

function record(fields:Array<[number,number,string]>) {
  const chars=Array(200).fill(" ");
  for(const[start,end,value]of fields){
    assert.ok(value.length<=end-start+1);
    Array.from(value.padEnd(end-start+1," ")).forEach((character,index)=>{chars[start-1+index]=character});
  }
  return chars.join("");
}

function fixture(carrier="ZZ",flightNumber=" 040"){
  return[
    record([[1,1,"1"],[2,80,"AIRLINE STANDARD SCHEDULE DATA SET"],[195,200,"000001"]]),
    record([[1,1,"2"],[2,2,"L"],[3,5,carrier],[15,21,"24OCT26"],[22,28,"26MAR27"],[29,35,"21SEP26"],[36,80,"ZENITH FULL SCHEDULE"],[195,200,"000002"]]),
    record([[1,1,"3"],[3,5,carrier],[6,9,flightNumber],[10,11,"01"],[12,13,"01"],[14,14,"J"],[15,21,"16JAN27"],[22,28,"25MAR27"],[29,35,"1  4 6 "],[37,39,"MLE"],[40,43,"1940"],[44,47,"1940"],[48,52,"+0500"],[53,54,"1"],[55,57,"RSI"],[58,61,"0040"],[62,65,"0040"],[66,70,"+0300"],[71,72,"1"],[73,75,"319"],[76,78,"XX"],[193,200,"01000003"]]),
    record([[1,1,"4"],[3,5,carrier],[6,9,flightNumber],[10,11,"01"],[12,13,"01"],[14,14,"J"],[29,30,"AB"],[31,33,"505"],[34,36,"MLE"],[37,39,"RSI"],[40,194,"ET"],[195,200,"000004"]]),
    record([[1,1,"5"],[3,5,carrier],[6,12,"21SEP26"],[193,200,"00000005"]]),
  ].join("\r\n");
}

test("parses fixed-width SSIM Chapter 7 records and attaches supplementary data",()=>{
  const result=parseSsimChapter7(fixture(),"ZZ");
  assert.equal(result.sourceCarrierIata,"ZZ");
  assert.equal(result.periodStart,"2026-10-24");
  assert.equal(result.periodEnd,"2027-03-26");
  assert.equal(result.seasonCode,"W26/27");
  assert.equal(result.records.length,5);
  assert.equal(result.records.filter(row=>row.parseStatus==="ERROR").length,0);
  assert.equal(result.legs.length,1);
  assert.partialDeepStrictEqual(result.legs[0],{
    flightNumber:"040",itineraryVariationIdentifier:"01",legSequenceNumber:1,operatingDays:"1001010",departureAirport:"MLE",arrivalAirport:"RSI",
    arrivalDayOffset:1,departureUtcOffsetMinutes:300,arrivalUtcOffsetMinutes:180,
    aircraftTypeIata:"319",aircraftConfiguration:"XX",
  });
  const supplementary=result.legs[0].additionalData.supplementaryRecords as Array<Record<string,unknown>>;
  assert.equal(supplementary.length,1);
  assert.equal(supplementary[0].dataElementCode,"505");
});

test("parses a flight number with a final alphabetic character",()=>{
  const result=parseSsimChapter7(fixture("ZZ","401A"),"ZZ");
  assert.equal(result.records.filter(row=>row.parseStatus==="ERROR").length,0);
  assert.equal(result.legs[0]?.flightNumber,"401A");
  const supplementary=result.legs[0]?.additionalData.supplementaryRecords as Array<Record<string,unknown>>;
  assert.equal(supplementary.length,1);
});

test("marks a carrier discrepancy as an error before staging",()=>{
  const result=parseSsimChapter7(fixture("PE"),"ZZ");
  assert.equal(result.legs.length,0);
  assert.ok(result.records.some(row=>row.validationMessages.some(message=>message.includes("workspace is ZZ"))));
});

test("marks malformed fixed-width records as errors and preserves the source line",()=>{
  const source=fixture().split("\r\n");
  source[2]=source[2].slice(0,199);
  const result=parseSsimChapter7(source.join("\n"),"ZZ");
  const failed=result.records.find(row=>row.lineNumber===3);
  assert.equal(failed?.parseStatus,"ERROR");
  assert.equal(failed?.rawRecord.length,199);
});
