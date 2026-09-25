import {test} from "node:test";
import assert from "node:assert/strict";
import {createSaveFeedback,initialSaveFeedback,type SaveFeedbackSnapshot} from "../src/domain/save-feedback";

function setup(){let latest:SaveFeedbackSnapshot=initialSaveFeedback;const controller=createSaveFeedback(value=>{latest=value;});return{controller,get snapshot(){return latest;}};}

test("a save waits for confirmation, then retains the editor until Exit without saving twice",async()=>{
 const state=setup();let release!:()=>void,requests=0,closed=0;
 const confirmation=new Promise<void>(resolve=>{release=resolve;});
 state.controller.select("row-one");
 const operation=state.controller.run(async()=>{requests++;await confirmation;state.controller.complete(()=>{closed++;});});
 assert.equal(state.snapshot.state,"saving");assert.equal(state.snapshot.busy,true);
 assert.equal(state.controller.select("row-two"),false);
 await state.controller.run(()=>{requests++;});
 assert.equal(requests,1);assert.equal(closed,0);
 release();await operation;
 assert.equal(state.snapshot.state,"saved");assert.equal(state.snapshot.activeId,"row-one");assert.equal(closed,0);
 await state.controller.run(()=>{requests++;});assert.equal(requests,1);
 state.controller.exit();assert.equal(closed,1);assert.deepEqual(state.snapshot,initialSaveFeedback);
 state.controller.exit();assert.equal(closed,1);
});

test("a rejected save never displays Saved and permits a retry",async()=>{
 const state=setup();state.controller.select("section");
 await state.controller.run(async()=>{/* Server returned validation failure; no complete call. */});
 assert.equal(state.snapshot.state,"editing");assert.equal(state.snapshot.busy,false);
 state.controller.select("section");await state.controller.run(()=>{state.controller.complete(()=>{});});
 assert.equal(state.snapshot.state,"saved");
});

test("a network exception preserves the editor and supplies a retry message",async()=>{
 const state=setup();let closed=false;state.controller.select("section");
 await state.controller.run(()=>{throw new Error("network unavailable");});
 assert.equal(state.snapshot.state,"editing");assert.match(state.snapshot.error,/entries are still here/);
 state.controller.exit();assert.equal(closed,false);
 state.controller.select("section");assert.equal(state.snapshot.error,"");
 await state.controller.run(()=>{state.controller.complete(()=>{closed=true;});});
 state.controller.exit();assert.equal(closed,true);
});

test("automatic checkbox updates do not leave a save receipt or block subsequent edits",async()=>{
 const state=setup();let applied=0;
 await state.controller.run(()=>{state.controller.complete(()=>{applied++;});});
 assert.equal(applied,1);assert.equal(state.snapshot.state,"editing");assert.equal(state.snapshot.busy,false);
});

test("cancel or a different control clears a save selection left by local validation",async()=>{
 const state=setup();state.controller.select("section");state.controller.clearSelection();
 await state.controller.run(()=>{state.controller.complete(()=>{});});
 assert.equal(state.snapshot.state,"editing");assert.equal(state.snapshot.activeId,null);
});
