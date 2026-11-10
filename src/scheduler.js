// Pure, deterministic rotation; scores reward work balancing across previous weeks.
export function dateAt(weekStart, offset){const d=new Date(weekStart+'T00:00:00Z');d.setUTCDate(d.getUTCDate()+offset);return d.toISOString().slice(0,10)}
export function mondayOf(date){const d=new Date(date+'T00:00:00Z');d.setUTCDate(d.getUTCDate()-((d.getUTCDay()+6)%7));return d.toISOString().slice(0,10)}
export function overlap(a,b){const toMinutes=v=>Number(v.slice(0,2))*60+Number(v.slice(3,5));const s=toMinutes(a.start_time),t=toMinutes(b.start_time);return s<t+b.duration_minutes&&t<s+a.duration_minutes}
/**
 * @param {{members:Array,chores:Array,availability:Array,history:Array,weekStart:string}} input
 * @returns {{rows:Array, warnings:Array}}
 */
export function generateWeek({members,chores,availability=[],history=[],weekStart}){
 const active=members.filter(m=>m.active!==false).slice().sort((a,b)=>String(a.user_id).localeCompare(String(b.user_id)))
 if(!active.length) return {rows:[],warnings:['Nhóm chưa có thành viên.']}
 const totals=new Map(active.map(m=>[m.user_id,0]));const byTask=new Map();const lastDay=new Map();const rows=[],warnings=[]
 for(const a of history){totals.set(a.assignee_id,(totals.get(a.assignee_id)||0)+Number(a.weight||1));const k=a.assignee_id+'|'+a.chore_id;byTask.set(k,(byTask.get(k)||0)+1);lastDay.set(k,a.work_date)}
 const sorted=chores.filter(c=>c.enabled!==false).slice().sort((a,b)=>String(a.start_time).localeCompare(String(b.start_time))||String(a.id).localeCompare(String(b.id)))
 for(let day=0;day<7;day++){
  const work_date=dateAt(weekStart,day),weekday=day+1,used=[]
  for(const chore of sorted.filter(c=>(c.weekdays||[]).includes(weekday))){
   const candidates=active.filter(m=>{
    const av=availability.find(x=>x.user_id===m.user_id&&x.weekday===weekday)
    return av?.available!==false&&!used.some(a=>a.assignee_id===m.user_id&&overlap(a,chore))
   }).map(m=>{
    const k=m.user_id+'|'+chore.id
    const repeated=byTask.get(k)||0
    const recent=lastDay.get(k)&&Math.abs((Date.parse(work_date)-Date.parse(lastDay.get(k)))/86400000)<=2?2:0
    return {m,score:(totals.get(m.user_id)||0)+Number(chore.weight||1)*repeated*2.5+recent}
   }).sort((a,b)=>a.score-b.score||String(a.m.user_id).localeCompare(String(b.m.user_id)))
   if(!candidates.length){warnings.push(`${work_date}: Không có người rảnh để làm ${chore.name}`);continue}
   const chosen=candidates[0].m;const row={room_id:chore.room_id,chore_id:chore.id,work_date,assignee_id:chosen.user_id,status:'pending',start_time:chore.start_time,duration_minutes:chore.duration_minutes,weight:chore.weight,name:chore.name}
   rows.push(row);used.push(row);totals.set(chosen.user_id,(totals.get(chosen.user_id)||0)+Number(chore.weight||1));const k=chosen.user_id+'|'+chore.id;byTask.set(k,(byTask.get(k)||0)+1);lastDay.set(k,work_date)
  }
 }
 return {rows,warnings}
}
