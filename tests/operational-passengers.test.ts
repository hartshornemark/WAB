import test from"node:test";
import assert from"node:assert/strict";
import{OperationalPassengerInvalid,passengerPlanningWeight,validateOperationalPassengerBooking}from"../src/domain/operational-passengers";

test("booked passenger simulation accepts a whole-number load by class",()=>{
 assert.deepEqual(validateOperationalPassengerBooking({classes:[{code:"J",booked:12},{code:"Y",booked:168}]}),{classes:[{code:"J",booked:12},{code:"Y",booked:168}]});
});
test("booked passenger simulation rejects duplicate classes and fractional loads",()=>{
 assert.throws(()=>validateOperationalPassengerBooking({classes:[{code:"Y",booked:12.5}]}),OperationalPassengerInvalid);
 assert.throws(()=>validateOperationalPassengerBooking({classes:[{code:"Y",booked:1},{code:"Y",booked:2}]}),OperationalPassengerInvalid);
});
test("planning uses Adult weight or a 50:50 Male/Female contribution",()=>{
 assert.equal(passengerPlanningWeight({adult:79,male:88,female:70,handBaggage:5,includesHandBaggage:true}),79);
 assert.equal(passengerPlanningWeight({adult:null,male:88,female:70,handBaggage:5,includesHandBaggage:true}),79);
 assert.equal(passengerPlanningWeight({adult:null,male:88,female:70,handBaggage:5,includesHandBaggage:false}),84);
});
