import test from 'node:test'
import assert from 'node:assert/strict'
import {createSyncController,ROOM_TOPICS,topicsForTable} from '../src/syncController.js'

test('Realtime topics are limited to the changed data slice',()=>{
 assert.deepEqual(topicsForTable('room_members'),['room_members','room_profiles'])
 assert.deepEqual(topicsForTable('assignments'),['assignments'])
 assert.deepEqual(topicsForTable('room_notifications'),['room_notifications'])
 assert.deepEqual(topicsForTable('chores'),['chores'])
 assert.deepEqual(topicsForTable('rooms'),['rooms'])
 assert.deepEqual(topicsForTable('unknown'),[])
 assert.equal(ROOM_TOPICS.length,9)
})
test('one hundred realtime events produce one network batch',async()=>{
 const batches=[]
 const controller=createSyncController({delay:5,execute:async topics=>batches.push(topics)})
 await Promise.all(Array.from({length:100},()=>controller.request('assignments')))
 assert.equal(batches.length,1)
 assert.deepEqual(batches[0],['assignments'])
 controller.dispose()
})
test('concurrent work is serialized, and new topics form only one subsequent batch',async()=>{
 const batches=[]
 let active=0,maxActive=0,release
 let startedResolve
 const started=new Promise(resolve=>{startedResolve=resolve})
 const controller=createSyncController({
  delay:1,
  execute:async topics=>{
   active++;maxActive=Math.max(maxActive,active)
   batches.push(topics)
   if(batches.length===1){
    startedResolve()
    await new Promise(resolve=>{release=resolve})
   }
   active--
  }
 })
 const first=controller.request('room_members',{immediate:true})
 await started
 const second=controller.request('assignments',{immediate:true})
 const third=controller.request('chores',{immediate:true})
 release()
 await Promise.all([first,second,third])
 assert.equal(maxActive,1)
 assert.deepEqual(batches,[['room_members'],['assignments','chores']])
 controller.dispose()
})
test('a full resynchronization replaces redundant per-table fetch requests',async()=>{
 const results=[]
 const c=createSyncController({delay:2,execute:async topics=>results.push(topics)})
 await Promise.all([c.request('assignments'),c.request('chores'),c.request(['all'])])
 assert.deepEqual(results,[['all']])
 c.dispose()
})
test('failed table fetch does not permanently poison synchronization',async()=>{
 let runs=0
 const errors=[]
 const c=createSyncController({delay:1,onError:e=>errors.push(e.message),execute:async()=>{
  runs++
  if(runs===1)throw new Error('offline')
 }})
 await assert.rejects(c.request('assignments'),/offline/)
 await c.request('assignments')
 assert.equal(runs,2)
 assert.deepEqual(errors,['offline'])
 c.dispose()
})
test('unmounted components cancel pending events without a late network request',async()=>{
 let runs=0
 const c=createSyncController({delay:100,execute:async()=>{runs++}})
 const promise=c.request('room_members')
 c.dispose()
 await promise
 assert.equal(runs,0)
})
