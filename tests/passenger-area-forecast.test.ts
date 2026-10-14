import test from"node:test";
import assert from"node:assert/strict";
import{forecastPassengerAreas}from"../src/domain/passenger-area-forecast";

test("passenger area forecast follows installed-seat proportions",()=>{
 assert.deepEqual(forecastPassengerAreas(112,[{areaId:"A",seats:36},{areaId:"B",seats:48},{areaId:"C",seats:48},{areaId:"D",seats:48}]),[
  {areaId:"A",seats:36,passengers:22},{areaId:"B",seats:48,passengers:30},{areaId:"C",seats:48,passengers:30},{areaId:"D",seats:48,passengers:30},
 ]);
});
