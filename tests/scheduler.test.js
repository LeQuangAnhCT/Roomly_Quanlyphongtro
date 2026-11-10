import test from 'node:test';import assert from 'node:assert/strict';import {generateWeek,mondayOf,overlap,dateAt,isBusy,isCooking} from '../src/scheduler.js'
test('week starts on Monday and dates cross months',()=>{assert.equal(mondayOf('2026-11-15'),'2026-11-09');assert.equal(dateAt('2026-11-30',6),'2026-12-06')})
test('does not double book overlapping jobs',()=>{const m=[{user_id:'a'},{user_id:'b'}];const c=['lunch','dinner'].map((name,i)=>({id:name,name,room_id:'r',start_time:'10:00',duration_minutes:60,weight:1,weekdays:[1]}));let x=generateWeek({members:m,chores:c,weekStart:'2026-11-09'});assert.equal(x.rows.length,2);assert.notEqual(x.rows[0].assignee_id,x.rows[1].assignee_id);assert.ok(overlap(c[0],c[1]))})
test('availability restricts assignment',()=>{const x=generateWeek({members:[{user_id:'a'},{user_id:'b'}],chores:[{id:'c',name:'cook',room_id:'r',start_time:'12:00',duration_minutes:60,weight:1,weekdays:[1]}],availability:[{user_id:'a',weekday:1,available:false}],weekStart:'2026-11-09'});assert.equal(x.rows[0].assignee_id,'b')})
test('warn when nobody available',()=>{const x=generateWeek({members:[{user_id:'a'}],chores:[{id:'c',name:'wash',room_id:'r',start_time:'08:00',duration_minutes:30,weight:1,weekdays:[1]}],availability:[{user_id:'a',weekday:1,available:false}],weekStart:'2026-11-09'});assert.equal(x.rows.length,0);assert.equal(x.warnings.length,1)})

test('repeat study schedule blocks only overlapping slots, not the whole day',()=>{
 const m=[{user_id:'a'},{user_id:'b'}]
 const chores=[
  {id:'l',name:'Nấu trưa',icon:'lunch',room_id:'r',start_time:'11:00',duration_minutes:60,weight:2,weekdays:[1]},
  {id:'d',name:'Nấu tối',icon:'dinner',room_id:'r',start_time:'18:00',duration_minutes:60,weight:2,weekdays:[1]}
 ]
 const busySlots=[{user_id:'a',weekday:1,busy_date:null,starts_at:'07:30',ends_at:'13:00',reason:'Đi học'}]
 const x=generateWeek({members:m,chores,busySlots,weekStart:'2026-11-09'})
 assert.equal(x.rows.find(a=>a.chore_id==='l').assignee_id,'b')
 assert.ok(x.rows.find(a=>a.chore_id==='d').assignee_id)
 assert.equal(isBusy({userId:'a',date:'2026-11-09',weekday:1,chore:chores[0],busySlots}),true)
 assert.equal(isBusy({userId:'a',date:'2026-11-09',weekday:1,chore:chores[1],busySlots}),false)
})
test('one-off unexpected busy time does not block recurring next week',()=>{
 const b=[{user_id:'a',busy_date:'2026-11-10',weekday:null,starts_at:'16:00',ends_at:'20:00'}]
 const c={start_time:'17:00',duration_minutes:90}
 assert.equal(isBusy({userId:'a',date:'2026-11-10',weekday:2,chore:c,busySlots:b}),true)
 assert.equal(isBusy({userId:'a',date:'2026-11-17',weekday:2,chore:c,busySlots:b}),false)
})
test('cooking runs in completed turns before repeating, lunch and dinner share queue',()=>{
 const members=['a','b','c','d'].map(user_id=>({user_id}))
 const chores=[{id:'l',icon:'lunch',name:'Nấu trưa',room_id:'r',start_time:'10:30',duration_minutes:60,weight:2,weekdays:[1,2,3,4,5,6,7]},
  {id:'d',icon:'dinner',name:'Nấu tối',room_id:'r',start_time:'17:30',duration_minutes:60,weight:2,weekdays:[1,2,3,4,5,6,7]}]
 const first=generateWeek({members,chores,weekStart:'2026-11-09'})
 assert.equal(first.rows.length,14)
 assert.equal(new Set(first.rows.slice(0,4).map(x=>x.assignee_id)).size,4)
 for(const day of Array.from({length:7},(_,i)=>i)){
  const selected=first.rows.filter(x=>x.work_date===dateAt('2026-11-09',day))
  assert.equal(new Set(selected.map(x=>x.assignee_id)).size,2)
 }
 const second=generateWeek({members,chores,history:first.rows,weekStart:'2026-11-16'})
 const all=[...first.rows,...second.rows]
 const counts=members.map(m=>all.filter(x=>x.assignee_id===m.user_id).length)
 assert.ok(Math.max(...counts)-Math.min(...counts)<=1,JSON.stringify(counts))
 assert.ok(isCooking(chores[0])&&isCooking(chores[1]))
})
test('busy all members results in warning, never invented assignment',()=>{
 const members=[{user_id:'a'},{user_id:'b'}]
 const chore={id:'l',icon:'lunch',name:'Nấu trưa',room_id:'r',start_time:'11:00',duration_minutes:90,weight:2,weekdays:[1]}
 const busySlots=members.map(m=>({user_id:m.user_id,weekday:1,starts_at:'07:00',ends_at:'14:00'}))
 const result=generateWeek({members,chores:[chore],busySlots,weekStart:'2026-11-09'})
 assert.equal(result.rows.length,0)
 assert.equal(result.warnings.length,1)
})
