/**
 * Roomly data synchronization coordinator.
 * Realtime messages only mark dirty data slices. There is at most one active
 * network batch; later events coalesce into the next batch. No router reload,
 * auth bootstrap, or room membership lookup is performed from this module.
 */
export const ROOM_TOPICS=Object.freeze([
 'room_members','chores','assignments','member_availability',
 'room_busy_slots','room_work_debts','swap_requests','room_notifications',
 'room_profiles'
])

export const ROOM_REALTIME_TABLES=Object.freeze(['rooms',...ROOM_TOPICS])

export function topicsForTable(table){
 if(table==='rooms')return ['rooms']
 if(table==='room_members')return ['room_members','room_profiles']
 if(ROOM_TOPICS.includes(table))return [table]
 return []
}

export function createSyncController({
 execute,
 onError=()=>{},
 delay=180,
 setTimer=setTimeout,
 clearTimer=clearTimeout
}){
 if(typeof execute!=='function')throw new TypeError('execute must be a function')
 const pending=new Set()
 let timeout=null
 let active=false
 let disposed=false
 let queueWaiters=[]
 let batches=0

 function schedule(wait=delay){
  if(disposed)return
  if(timeout!==null)clearTimer(timeout)
  timeout=setTimer(()=>{
   timeout=null
   void drain()
  },wait)
 }
 function request(topics=['all'],{immediate=false}={}){
  if(disposed)return Promise.resolve()
  const list=Array.isArray(topics)?topics:[topics]
  if(!list.length)return Promise.resolve()
  for(const topic of list){
   if(topic==='all'){pending.clear();pending.add('all');break}
   if(!pending.has('all'))pending.add(topic)
  }
  return new Promise((resolve,reject)=>{
   queueWaiters.push({resolve,reject})
   if(!active)schedule(immediate?0:delay)
  })
 }
 async function drain(){
  if(disposed||active||!pending.size)return
  active=true
  if(timeout!==null){clearTimer(timeout);timeout=null}
  const batch=[...pending];pending.clear()
  const waiters=queueWaiters;queueWaiters=[]
  try{
   batches++
   await execute(batch)
   for(const w of waiters)w.resolve()
  }catch(e){
   try{onError(e)}catch{}
   for(const w of waiters)w.reject(e)
  }finally{
   active=false
   if(pending.size&&!disposed)schedule(0)
  }
 }
 function dispose(){
  disposed=true
  pending.clear()
  if(timeout!==null){clearTimer(timeout);timeout=null}
  for(const w of queueWaiters)w.resolve()
  queueWaiters=[]
 }
 return {
  request,
  flush:drain,
  dispose,
  get pending(){return [...pending]},
  get active(){return active},
  get batches(){return batches}
 }
}
