<script setup>
import {computed,onMounted,onUnmounted,ref,watch} from 'vue'
import {House,CalendarDays,UsersRound,ListTodo,BarChart3,Settings,LogOut,Bell,Plus,ChevronLeft,ChevronRight,ChevronDown,Check,CheckCircle2,Clock3,Utensils,Sun,Shirt,Droplets,Shuffle,Trash2,Pencil,Copy,X,RefreshCw,ArrowRightLeft,Menu,AlertCircle,ShieldCheck,LoaderCircle} from 'lucide-vue-next'
import {supabase,configured,check} from './supabase.js'
import {generateWeek,mondayOf,dateAt,isBusy,overlap} from './scheduler.js'
const iconFor={lunch:Utensils,dinner:Utensils,wash:Shirt,dry:Sun,water:Droplets}
const user=ref(null),booting=ref(true),busy=ref(false),message=ref(''),error=ref(''),loginEmail=ref(''),emailSent=ref(false)
const currentTab=ref('schedule'),modal=ref(''),menuOpen=ref(false),room=ref(null),members=ref([]),chores=ref([]),assignments=ref([]),availability=ref([]),busySlots=ref([]),debts=ref([]),swaps=ref([]),notifications=ref([]),profiles=ref([])
const weekStart=ref(mondayOf(new Date().toISOString().slice(0,10))),selectedDay=ref(new Date().toISOString().slice(0,10))
const busyDraft=ref({mode:'weekly',weekday:1,busy_date:'',starts_at:'07:00',ends_at:'12:00',reason:'Đi học'}),debtDraft=ref({debt_id:'',chore_id:'',work_date:''}),debtReason=ref(''),filter=ref('all'),draft=ref({}),joinCode=ref(''),groupName=ref(''),draftName=ref(''),newRecipient=ref(''),activeAssignment=ref(null),warnings=ref([]),showCompleted=ref(true),manualChore=ref(''),manualPerson=ref(''),roomDraft=ref('')
const fullName=computed(()=>profiles.value.find(p=>p.user_id===user.value?.id)?.display_name||user.value?.user_metadata?.full_name||user.value?.email?.split('@')[0]||'Bạn')
const isOwner=computed(()=>room.value?.owner_id===user.value?.id)
const weekdays=['T2','T3','T4','T5','T6','T7','CN']
const weekDays=computed(()=>Array.from({length:7},(_,i)=>({date:dateAt(weekStart.value,i),label:weekdays[i],num:Number(dateAt(weekStart.value,i).slice(-2))})))
const nameOf=id=>profiles.value.find(p=>p.user_id===id)?.display_name||members.value.find(m=>m.user_id===id)?.email||('Thành viên '+String(id||'').slice(0,4))
const initials=id=>nameOf(id).trim().split(/\s+/).slice(-2).map(s=>s[0]).join('').toUpperCase()
const choreOf=id=>chores.value.find(c=>c.id===id)
const formatClock=t=>t?.slice(0,5)||''
const selectedAssignments=computed(()=>assignments.value.filter(a=>a.work_date===selectedDay.value).filter(a=>filter.value==='all'||filter.value===a.assignee_id).filter(a=>showCompleted.value||a.status!=='done').sort((a,b)=>String(choreOf(a.chore_id)?.start_time||'').localeCompare(String(choreOf(b.chore_id)?.start_time||''))))
const myTasks=computed(()=>assignments.value.filter(a=>a.assignee_id===user.value?.id))
const myDone=computed(()=>myTasks.value.filter(a=>a.status==='done').length)
const pendingSwaps=computed(()=>swaps.value.filter(s=>s.to_user===user.value?.id&&s.status==='pending'))
const unread=computed(()=>notifications.value.filter(n=>!n.read_at).length)
const myBusy=computed(()=>busySlots.value.filter(b=>b.user_id===user.value?.id).sort((a,b)=>String(a.busy_date||a.weekday).localeCompare(String(b.busy_date||b.weekday))||a.starts_at.localeCompare(b.starts_at)))
const owedDebts=computed(()=>debts.value.filter(d=>d.status==='owed'))
const myDebts=computed(()=>owedDebts.value.filter(d=>d.user_id===user.value?.id))
const formatBusy=b=>b.busy_date ? b.busy_date.split('-').reverse().join('/') : weekdays[Number(b.weekday)-1]
function canTakeTransfer(personId,assignment) {
 const c=choreOf(assignment.chore_id)
 if(!c||personId===assignment.assignee_id)return false
 const day=(new Date(assignment.work_date+'T00:00:00Z').getUTCDay()+6)%7+1
 return !isBusy({userId:personId,date:assignment.work_date,weekday:day,chore:c,busySlots:busySlots.value,availability:availability.value}) &&
  !assignments.value.some(a=>a.id!==assignment.id && a.assignee_id===personId &&
   a.work_date===assignment.work_date && a.status!=='skipped' && overlap(choreOf(a.chore_id)||c,c))
}
const transferCandidates=computed(()=>activeAssignment.value ? members.value.filter(m=>canTakeTransfer(m.user_id,activeAssignment.value)) : [])

const stats=computed(()=>members.value.filter(m=>m.active).map(m=>{const assigned=assignments.value.filter(a=>a.assignee_id===m.user_id);return {...m,assigned:assigned.length,done:assigned.filter(a=>a.status==='done').length,points:assigned.reduce((n,a)=>n+Number(choreOf(a.chore_id)?.weight||1),0)}}))
function toast(s,fail=false){if(fail)error.value=s;else message.value=s;setTimeout(()=>{message.value='';error.value=''},5000)}
function localErr(e){
 const message=String(e?.message||'Không thể hoàn tất thao tác.')
 if(/provider.*(not enabled|disabled|not supported)|unsupported provider/i.test(message))
   return 'Đăng nhập Google chưa được bật trong Supabase Roomly. Có thể thử đăng nhập bằng email hoặc liên hệ trưởng nhóm để bật Google OAuth.'
 if(/redirect|callback|oauth client|invalid client/i.test(message))
   return 'Cấu hình đăng nhập Google chưa đúng. Cần kiểm tra Redirect URL trên Supabase và Google Cloud.'
 if(/otp.*disabled|email.*disabled/i.test(message))
   return 'Đăng nhập email chưa được bật trong Supabase Roomly.'
 return message
}
async function run(fn){if(busy.value)return;busy.value=true;error.value='';try{await fn()}catch(e){toast(localErr(e),true)}finally{busy.value=false}}
async function login(){
 if(!configured)return toast('Chưa cấu hình Supabase.',true)
 await run(async()=>{
  const {data,error:signInError}=await supabase.auth.signInWithOAuth({
   provider:'google',
   options:{redirectTo:window.location.origin+'/',skipBrowserRedirect:true}
  })
  if(signInError)throw signInError
  if(!data?.url)throw new Error('Không tạo được liên kết đăng nhập Google.')
  window.location.assign(data.url)
 })
}
async function emailLogin(){await run(async()=>{const email=loginEmail.value.trim().toLowerCase();if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))throw Error('Nhập địa chỉ email hợp lệ');await check(await supabase.auth.signInWithOtp({email,options:{emailRedirectTo:location.origin,shouldCreateUser:true}}));emailSent.value=true;toast('Đã gửi liên kết đăng nhập. Kiểm tra hộp thư của bạn.')})}
async function logout(){await run(async()=>{await check(await supabase.auth.signOut({scope:'local'}));reset();toast('Đã đăng xuất')})}
function reset(){room.value=null;members.value=[];chores.value=[];assignments.value=[];profiles.value=[];availability.value=[];busySlots.value=[];debts.value=[];swaps.value=[];notifications.value=[];currentTab.value='schedule';modal.value=''}
let authSubscription=null
let sessionRevision=0
async function init(){
 if(!configured){booting.value=false;return}
 // Never issue Supabase queries inside the synchronous auth-state callback.
 // Deferring also prevents OAuth initialization and getSession from double-loading.
 authSubscription=supabase.auth.onAuthStateChange((_event,session)=>{
  const next=session?.user||null
  const changed=next?.id!==user.value?.id
  user.value=next
  if(changed){
   const revision=++sessionRevision
   reset()
   if(next)setTimeout(()=>{if(revision===sessionRevision)loadEverything()},0)
  }
 }).data.subscription
 try{
  const {data,error:sessionError}=await supabase.auth.getSession()
  if(sessionError)throw sessionError
  const next=data?.session?.user||null
  if(next?.id!==user.value?.id){user.value=next;sessionRevision++;if(next)await loadEverything()}
 }catch(err){
  // Authentication errors must never trap the app on the splash screen.
  toast(localErr(err),true)
 }finally{
  booting.value=false
  const q=new URLSearchParams(location.search)
  const fragment=new URLSearchParams(location.hash.replace(/^#/,''))
  const errorCode=q.get('error')||fragment.get('error')
  const errorDescription=q.get('error_description')||fragment.get('error_description')
  if(errorCode||errorDescription){
   toast(localErr(new Error(errorDescription||errorCode)),true)
   // Remove failed OAuth query parameters but keep the normal app URL.
   history.replaceState(null,'',location.pathname)
  }
 }
}
async function loadEverything(){if(!user.value)return;try{
 const own=await check(await supabase.from('room_members').select('room_id,active').eq('user_id',user.value.id).eq('active',true).limit(1));
 if(!own?.length){reset();await ensureProfile();return}
 const r=await check(await supabase.from('rooms').select('*').eq('id',own[0].room_id).single());room.value=r;await ensureProfile();await refresh()
 }catch(e){toast(localErr(e),true)}finally{booting.value=false}}
async function ensureProfile(){if(!user.value)return;const p={user_id:user.value.id,display_name:user.value.user_metadata?.full_name||user.value.email?.split('@')[0]||'Thành viên',avatar_url:user.value.user_metadata?.avatar_url||null};const existing=await check(await supabase.from('room_profiles').select('user_id').eq('user_id',user.value.id).maybeSingle());if(!existing)await check(await supabase.from('room_profiles').insert(p))}
async function refresh(){if(!room.value)return;const id=room.value.id;const results=await Promise.all([
 supabase.from('room_members').select('*').eq('room_id',id).eq('active',true),
 supabase.from('chores').select('*').eq('room_id',id).order('start_time'),
 supabase.from('assignments').select('*').eq('room_id',id).gte('work_date',dateAt(weekStart.value,-28)).lte('work_date',dateAt(weekStart.value,6)).order('work_date'),
 supabase.from('member_availability').select('*').eq('room_id',id),
 supabase.from('room_busy_slots').select('*').eq('room_id',id).order('starts_at'),
 supabase.from('room_work_debts').select('*').eq('room_id',id).order('created_at',{ascending:false}),
 supabase.from('swap_requests').select('*').eq('room_id',id).order('created_at',{ascending:false}),
 supabase.from('room_notifications').select('*').eq('user_id',user.value.id).order('created_at',{ascending:false}).limit(50)
 ]);const [m,c,a,v,b,d,s,n]=await Promise.all(results.map(check));members.value=m;chores.value=c;assignments.value=a;availability.value=v;busySlots.value=b;debts.value=d;swaps.value=s;notifications.value=n;
 profiles.value=m.length?await check(await supabase.from('room_profiles').select('user_id,display_name,avatar_url').in('user_id',m.map(x=>x.user_id))):[]}
async function createRoom(){await run(async()=>{if(!groupName.value.trim())throw Error('Nhập tên nhóm trọ');await check(await supabase.rpc('room_create',{p_name:groupName.value.trim()}));groupName.value='';await loadEverything();toast('Đã tạo nhóm trọ')})}
async function joinRoom(){await run(async()=>{if(!joinCode.value.trim())throw Error('Nhập mã mời');await check(await supabase.rpc('room_join',{p_code:joinCode.value.trim()}));joinCode.value='';await loadEverything();toast('Đã gia nhập nhóm trọ')})}
async function copyCode(){try{await navigator.clipboard.writeText(room.value.invite_code);toast('Đã sao chép mã mời')}catch{toast('Mã mời: '+room.value.invite_code)}}
async function removeMember(id){if(!confirm('Xóa thành viên khỏi nhóm?'))return;await run(async()=>{await check(await supabase.rpc('room_remove_member',{p_room:room.value.id,p_user:id}));await refresh();toast('Đã xóa thành viên')})}
async function leaveRoom(){if(!confirm('Bạn muốn rời nhóm trọ?'))return;await run(async()=>{await check(await supabase.rpc('room_leave',{p_room:room.value.id}));reset();toast('Đã rời nhóm trọ')})}
function openChore(chore=null){draft.value=chore?{...chore,weekdays:[...chore.weekdays]}:{name:'',icon:'sparkles',weight:1,start_time:'09:00',duration_minutes:30,weekdays:[1,2,3,4,5,6,7],enabled:true};modal.value='chore'}
async function saveChore(){await run(async()=>{const d=draft.value;const values={room_id:room.value.id,name:d.name?.trim(),icon:d.icon||'sparkles',weight:Number(d.weight),start_time:d.start_time,duration_minutes:Number(d.duration_minutes),weekdays:d.weekdays,enabled:Boolean(d.enabled)};if(!values.name||!values.weekdays.length)throw Error('Nhập tên việc và chọn ít nhất một ngày');if(d.id)await check(await supabase.from('chores').update(values).eq('id',d.id));else await check(await supabase.from('chores').insert(values));modal.value='';await refresh();toast('Đã lưu công việc')})}
async function deleteChore(id){if(!confirm('Xóa công việc này và các lịch liên quan?'))return;await run(async()=>{await check(await supabase.from('chores').delete().eq('id',id));modal.value='';await refresh();toast('Đã xóa công việc')})}
function toggleWeekday(d){draft.value.weekdays=draft.value.weekdays.includes(d)?draft.value.weekdays.filter(x=>x!==d):[...draft.value.weekdays,d].sort()}
function moveWeek(n){weekStart.value=dateAt(weekStart.value,n*7);selectedDay.value=weekStart.value;refresh().catch(e=>toast(localErr(e),true))}
async function saveManual(){await run(async()=>{if(!manualChore.value||!manualPerson.value)throw Error('Chọn công việc và người thực hiện');await check(await supabase.rpc('room_assign_manual',{p_room:room.value.id,p_chore:manualChore.value,p_date:selectedDay.value,p_user:manualPerson.value}));modal.value='';await refresh();toast('Đã phân công thủ công')})}
async function renameRoom(){await run(async()=>{await check(await supabase.rpc('room_rename',{p_room:room.value.id,p_name:roomDraft.value}));room.value={...room.value,name:roomDraft.value.trim()};modal.value='';toast('Đã đổi tên nhóm')})}
async function disbandRoom(){if(!confirm('Giải tán nhóm sẽ xóa toàn bộ lịch, thành viên và dữ liệu nhóm. Bạn chắc chắn?'))return;await run(async()=>{await check(await supabase.rpc('room_disband',{p_room:room.value.id}));reset();toast('Đã giải tán nhóm')})}
async function autoSchedule(){if(!isOwner.value)return;const existing=assignments.value.filter(a=>a.work_date<weekStart.value);const future=assignments.value.filter(a=>a.work_date>=weekStart.value&&a.work_date<=dateAt(weekStart.value,6));if(future.some(a=>a.status!=='pending'||a.makeup_debt_id))return toast('Tuần có việc đã hoàn thành, bị nợ hoặc lịch bù nên không thể tạo lại.',true);const result=generateWeek({members:members.value,chores:chores.value,availability:availability.value,busySlots:busySlots.value,history:existing.map(a=>({...a,weight:choreOf(a.chore_id)?.weight||1})),weekStart:weekStart.value});warnings.value=result.warnings; if(!result.rows.length)return toast('Không có việc nào để phân. Kiểm tra ngày rảnh hoặc danh mục việc.',true);if(!confirm(`Phân ${result.rows.length} lượt việc trong tuần? Lịch chưa hoàn thành của tuần này sẽ được tạo lại.`))return;await run(async()=>{await check(await supabase.rpc('room_replace_week',{p_room:room.value.id,p_start:weekStart.value,p_rows:result.rows.map(({room_id,chore_id,work_date,assignee_id})=>({chore_id,work_date,assignee_id}))}));await refresh();toast(`Đã phân ${result.rows.length} công việc`);modal.value=warnings.value.length?'warnings':''})}
async function complete(a){await run(async()=>{await check(await supabase.rpc('room_complete_assignment',{p_id:a.id,p_done:a.status!=='done'}));await refresh();toast(a.status==='done'?'Đã hoàn tác':'Đã đánh dấu hoàn thành')})}
function openSwap(a){activeAssignment.value=a;newRecipient.value='';debtReason.value='';modal.value='swap'}
async function requestSwap(){await run(async()=>{if(!newRecipient.value||!canTakeTransfer(newRecipient.value,activeAssignment.value))throw Error('Chọn thành viên rảnh và không trùng giờ');await check(await supabase.from('swap_requests').insert({room_id:room.value.id,assignment_id:activeAssignment.value.id,from_user:user.value.id,to_user:newRecipient.value}));modal.value='';await refresh();toast('Đã gửi yêu cầu đổi việc')})}
async function decideSwap(s,accept){await run(async()=>{await check(await supabase.rpc('room_resolve_swap',{p_id:s.id,p_accept:accept}));await refresh();toast(accept?'Đã nhận việc':'Đã từ chối')})}
function openBusy(){
 busyDraft.value={mode:'weekly',weekday:1,busy_date:selectedDay.value,starts_at:'07:00',ends_at:'12:00',reason:'Đi học'}
 modal.value='busy'
}
async function saveBusy(){
 await run(async()=>{
  const d=busyDraft.value
  if(!d.starts_at||!d.ends_at||d.starts_at>=d.ends_at)throw Error('Giờ kết thúc phải sau giờ bắt đầu')
  if(!d.reason?.trim())throw Error('Nhập lý do bận')
  const payload={room_id:room.value.id,user_id:user.value.id,
   weekday:d.mode==='weekly'?Number(d.weekday):null,
   busy_date:d.mode==='date'?d.busy_date:null,
   starts_at:d.starts_at,ends_at:d.ends_at,reason:d.reason.trim()}
  if(d.mode==='date'&&!d.busy_date)throw Error('Chọn ngày bận')
  await check(await supabase.from('room_busy_slots').insert(payload))
  modal.value=''
  await refresh()
  toast('Đã lưu lịch bận; các lần tự phân công sau sẽ tránh giờ này.')
 })
}
async function removeBusy(id){
 if(!confirm('Xóa khoảng thời gian bận này?'))return
 await run(async()=>{await check(await supabase.from('room_busy_slots').delete().eq('id',id).eq('user_id',user.value.id));await refresh();toast('Đã xóa lịch bận')})
}
async function markDebt(){
 if(!activeAssignment.value)return
 if(!confirm('Chưa tìm được người nhận? Việc sẽ được đánh dấu chưa làm và ghi nợ để bù sau.'))return
 await run(async()=>{
  await check(await supabase.rpc('room_mark_uncovered',{p_assignment:activeAssignment.value.id,p_reason:debtReason.value}))
  modal.value=''
  await refresh()
  toast('Đã ghi nợ việc. Trưởng nhóm có thể phân ca bù sau.')
 })
}
function openMakeup(debt){
 debtDraft.value={debt_id:debt.id,chore_id:chores.value.find(c=>c.enabled)?.id||'',work_date:dateAt(weekStart.value,7)}
 modal.value='makeup'
}
async function scheduleMakeup(){
 await run(async()=>{
  const d=debtDraft.value
  if(!d.chore_id||!d.work_date)throw Error('Chọn công việc và ngày bù')
  await check(await supabase.rpc('room_schedule_makeup',{p_debt:d.debt_id,p_chore:d.chore_id,p_date:d.work_date}))
  modal.value=''
  await refresh()
  toast('Đã lên lịch bù. Nợ chỉ được xóa sau khi hoàn thành việc bù.')
 })
}
async function toggleAvailability(day){await run(async()=>{const old=availability.value.find(a=>a.user_id===user.value.id&&a.weekday===day);await check(await supabase.from('member_availability').upsert({room_id:room.value.id,user_id:user.value.id,weekday:day,available:old?.available===false}));await refresh()})}
async function saveProfile(){await run(async()=>{const value=draftName.value.trim();if(!value||value.length>60)throw Error('Tên phải từ 1 đến 60 ký tự');await check(await supabase.from('room_profiles').update({display_name:value,updated_at:new Date().toISOString()}).eq('user_id',user.value.id));modal.value='';await refresh();toast('Đã cập nhật hồ sơ')})}
async function readNotifications(){await run(async()=>{await check(await supabase.from('room_notifications').update({read_at:new Date().toISOString()}).eq('user_id',user.value.id).is('read_at',null));await refresh()})}
let channel=null;watch(()=>room.value?.id,id=>{if(channel){supabase.removeChannel(channel);channel=null}if(id&&supabase){channel=supabase.channel('roomly-'+id).on('postgres_changes',{event:'*',schema:'public',table:'assignments',filter:'room_id=eq.'+id},()=>refresh().catch(()=>{})).subscribe()}})
onMounted(init);onUnmounted(()=>{authSubscription?.unsubscribe();if(channel&&supabase)supabase.removeChannel(channel)})
</script>

<template>
<div class="app-root">
  <div v-if="booting" class="center-screen"><div class="brand-icon large"><House :size="30"/></div><h1>ROOMLY</h1><LoaderCircle class="spin" :size="24"/><p>Đang khởi động ứng dụng...</p></div>
  <div v-else-if="!configured" class="center-screen"><div class="brand-icon large"><House :size="30"/></div><h1>ROOMLY</h1><p>Chưa cấu hình Supabase. Thêm VITE_SUPABASE_URL và VITE_SUPABASE_PUBLISHABLE_KEY trong Vercel.</p></div>
  <div v-else-if="!user" class="login-screen"><div class="brand-top"><div class="brand-icon"><House :size="25"/></div><b>ROOMLY</b></div><div class="login-content"><span class="eyebrow">KHÔNG GIAN SỐNG CHUNG</span><h1>Ở chung dễ dàng.<br><span>Chia việc công bằng.</span></h1><p>Lên lịch nấu ăn, giặt giũ, phơi đồ và mọi công việc trong phòng trọ — minh bạch suốt 7 ngày.</p><button class="btn btn-dark login-btn" :disabled="busy" @click="login"><svg width="21" height="21" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 8.11 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.28 5.48-4.82 7.18l7.73 6C44.36 38.03 46.98 31.88 46.98 24.55z"/><path fill="#FBBC05" d="M10.53 28.59A14.4 14.4 0 0 1 9.75 24c0-1.59.27-3.13.76-4.59l-7.98-6.19A23.87 23.87 0 0 0 0 24c0 3.87.93 7.53 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.92-2.13 15.89-5.8l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg> Tiếp tục với Google</button><small>Đăng nhập bằng Google hoặc nhận liên kết qua email.</small><p v-if="error" role="alert" class="login-error">{{error}}</p><div class="email-login"><label for="loginEmail">Đăng nhập bằng email</label><div class="email-login-row"><input id="loginEmail" type="email" autocomplete="email" v-model="loginEmail" placeholder="email@example.com"/><button class="btn btn-outline" :disabled="busy" @click="emailLogin">Gửi liên kết</button></div><p v-if="emailSent" role="status">Đã gửi email. Hãy kiểm tra hộp thư, kể cả thư rác.</p></div></div><footer>© 2026 ROOMLY · Đơn giản · Công bằng</footer></div>
  <div v-else-if="!room" class="onboard-screen"><header class="app-header"><div class="brand"><span class="brand-icon"><House :size="20"/></span><b>ROOMLY</b></div><button class="icon-button" title="Đăng xuất" @click="logout"><LogOut :size="20"/></button></header><div class="onboard"><span class="eyebrow">CHÀO MỪNG BẠN</span><h1>Bắt đầu với nhóm trọ</h1><p>Tạo nhóm mới để quản lý hoặc nhập mã mời của nhóm đã có.</p><div class="surface"><h3><House :size="20"/> Tạo nhóm mới</h3><label>Tên nhóm trọ</label><input v-model="groupName" placeholder="Ví dụ: Phòng trọ 2026" maxlength="80"/><button class="btn btn-dark" :disabled="busy" @click="createRoom"><Plus :size="17"/> Tạo nhóm trọ</button></div><div class="or">HOẶC</div><div class="surface"><h3><UsersRound :size="20"/> Tham gia nhóm</h3><label>Mã mời nhóm trọ</label><input v-model="joinCode" placeholder="Nhập mã 10 ký tự" maxlength="10"/><button class="btn btn-outline" :disabled="busy" @click="joinRoom">Gia nhập nhóm</button></div></div></div>
  <div v-else class="workspace"><header class="app-header"><div class="brand"><span class="brand-icon"><House :size="20"/></span><span><b>ROOMLY</b><small>{{room.name}} · {{members.length}} thành viên</small></span></div><div class="header-actions"><button class="icon-button notification-button" title="Thông báo" @click="currentTab='notifications'"><Bell :size="20"/><i v-if="unread">{{unread}}</i></button><button class="avatar-button" @click="menuOpen=!menuOpen">{{initials(user.id)}}</button><Transition name="fade"><div v-if="menuOpen" class="account-popover"><strong>{{fullName}}</strong><small>{{user.email}}</small><button @click="draftName=fullName;modal='profile';menuOpen=false"><Pencil :size="16"/> Chỉnh sửa tên</button><button @click="currentTab='settings';menuOpen=false"><Settings :size="16"/> Cài đặt</button><button @click="logout"><LogOut :size="16"/> Đăng xuất</button></div></Transition></div></header>
  <main class="main-area">
   <Transition name="page" mode="out-in">
   <section v-if="currentTab==='schedule'" key="schedule" class="content-panel"><div class="title-line"><div><span class="eyebrow">PHÂN CÔNG 7 NGÀY</span><h1>Lịch việc nhà</h1><p>Ai làm việc gì? Xem nhanh trong tuần.</p></div><button class="icon-button refresh" @click="refresh" title="Làm mới"><RefreshCw :size="19"/></button></div>
    <div class="dark-summary"><div><small>Việc của bạn trong tuần</small><strong>{{myDone}} / {{myTasks.length}}</strong><span>Đã hoàn thành</span></div><CheckCircle2 :size="30"/><div class="progress"><div :style="{width:myTasks.length?myDone/myTasks.length*100+'%':'0%'}"></div></div></div>
    <div class="surface week-panel"><div class="section-title"><strong>Tuần {{weekStart.slice(8)}}/{{weekStart.slice(5,7)}} – {{dateAt(weekStart,6).slice(8)}}/{{dateAt(weekStart,6).slice(5,7)}}</strong><div class="week-arrows"><button @click="moveWeek(-1)"><ChevronLeft :size="18"/></button><button @click="moveWeek(1)"><ChevronRight :size="18"/></button></div></div><div class="week-days"><button v-for="day in weekDays" :key="day.date" :class="{'is-active':selectedDay===day.date}" @click="selectedDay=day.date"><span>{{day.label}}</span><b>{{day.num}}</b><i></i></button></div></div>
    <div class="section-title after-week"><div><h2>{{weekDays.find(d=>d.date===selectedDay)?.label}}, {{selectedDay.slice(8,10)}}/{{selectedDay.slice(5,7)}}</h2><small>{{selectedAssignments.length}} công việc</small></div><select v-model="filter" aria-label="Lọc nhân viên"><option value="all">Tất cả</option><option v-for="m in members" :key="m.user_id" :value="m.user_id">{{nameOf(m.user_id)}}</option></select></div>
    <div v-if="!selectedAssignments.length" class="empty"><CalendarDays :size="30"/><b>Chưa có việc trong ngày</b><p>Trưởng nhóm có thể tạo lịch tự động để phân việc.</p></div>
    <div v-for="a in selectedAssignments" :key="a.id" class="task-card"><div class="task-top"><div class="task-icon"><component :is="iconFor[choreOf(a.chore_id)?.icon]||ListTodo" :size="20"/></div><div class="task-name"><b>{{choreOf(a.chore_id)?.name||'Công việc'}}</b><small><Clock3 :size="13"/> {{formatClock(choreOf(a.chore_id)?.start_time)}} · {{choreOf(a.chore_id)?.duration_minutes}} phút</small></div><span class="state" :class="a.status">{{a.status==='done'?'Đã xong':a.status==='skipped'?'Bỏ qua':'Chưa làm'}}</span></div><div class="task-bottom"><span class="person-pill"><span class="mini-avatar">{{initials(a.assignee_id)}}</span> {{nameOf(a.assignee_id)}}</span><div class="task-actions"><button v-if="a.assignee_id===user.id" class="small-button" :disabled="busy" @click="complete(a)"><Check :size="14"/> {{a.status==='done'?'Hoàn tác':'Hoàn thành'}}</button><button v-if="a.assignee_id===user.id&&a.status==='pending'" class="small-button" @click="openSwap(a)"><ArrowRightLeft :size="14"/> Đổi</button></div></div></div>
    <div v-if="isOwner" class="actions-sticky"><button class="btn btn-outline" @click="manualChore='';manualPerson='';modal='manual'"><Plus :size="17"/> Phân công thủ công</button><button class="btn btn-dark" :disabled="busy" @click="autoSchedule"><Shuffle :size="17"/> Tự động phân lịch tuần</button></div>
   </section>
   <section v-else-if="currentTab==='members'" key="members" class="content-panel"><div class="title-line"><div><span class="eyebrow">KHÔNG GIAN SỐNG CHUNG</span><h1>Nhóm trọ</h1><p>Quản lý {{members.length}} thành viên trong nhóm.</p></div></div><div class="surface invite-card"><div><small>MÃ MỜI THÀNH VIÊN</small><strong>{{room.invite_code}}</strong></div><button class="btn btn-outline" @click="copyCode"><Copy :size="16"/> Sao chép</button></div><h2 class="subheading">Thành viên</h2><div v-for="m in members" :key="m.user_id" class="member-card"><span class="member-avatar">{{initials(m.user_id)}}</span><div class="member-info"><b>{{nameOf(m.user_id)}}</b><small>{{m.user_id===room.owner_id?'Trưởng nhóm':'Thành viên'}} · {{stats.find(x=>x.user_id===m.user_id)?.assigned||0}} lượt việc</small></div><button v-if="isOwner&&m.user_id!==user.id" class="icon-button danger" title="Xóa thành viên" @click="removeMember(m.user_id)"><Trash2 :size="18"/></button></div><div class="surface availability-card"><h3>Ngày tôi có thể làm việc</h3><p>Chọn ngày rảnh để phân lịch chính xác hơn.</p><div class="day-options"><button v-for="(label,i) in weekdays" :key="i" :class="{selected:availability.find(a=>a.user_id===user.id&&a.weekday===i+1)?.available!==false}" @click="toggleAvailability(i+1)">{{label}}</button></div></div><button v-if="!isOwner" class="btn btn-outline leave" @click="leaveRoom">Rời nhóm trọ</button></section>
   <section v-else-if="currentTab==='chores'" key="chores" class="content-panel"><div class="title-line"><div><span class="eyebrow">CÔNG VIỆC ĐỊNH KỲ</span><h1>Danh mục việc</h1><p>Thiết lập việc nhà và lịch lặp mỗi tuần.</p></div><button v-if="isOwner" class="icon-button primary-icon" title="Thêm công việc" @click="openChore()"><Plus :size="21"/></button></div><div v-for="c in chores" :key="c.id" class="chore-card"><div class="task-icon"><component :is="iconFor[c.icon]||ListTodo" :size="20"/></div><div class="chore-info"><b>{{c.name}}</b><small>{{formatClock(c.start_time)}} · {{c.duration_minutes}} phút · {{c.weekdays.length}} ngày/tuần</small><span>{{c.weight}} điểm · {{c.enabled?'Đang áp dụng':'Tạm dừng'}}</span></div><button v-if="isOwner" class="icon-button" @click="openChore(c)" title="Sửa công việc"><Pencil :size="17"/></button></div><div class="notice"><AlertCircle :size="17"/><span>Điểm công việc dùng để chia công sức công bằng, không phải tiền lương.</span></div></section>
   <section v-else-if="currentTab==='stats'" key="stats" class="content-panel"><div class="title-line"><div><span class="eyebrow">MINH BẠCH & CÔNG BẰNG</span><h1>Thống kê</h1><p>Tổng hợp tuần bắt đầu {{weekStart.slice(8)}}/{{weekStart.slice(5,7)}}.</p></div></div><div class="surface"><h3>Điểm công việc theo người</h3><div v-for="s in stats" :key="s.user_id" class="stat-person"><div class="stat-caption"><span>{{nameOf(s.user_id)}}</span><b>{{s.points}} điểm</b></div><div class="stat-bar"><div :style="{width:100*s.points/Math.max(...stats.map(x=>x.points),1)+'%'}"></div></div><small>{{s.done}}/{{s.assigned}} việc hoàn thành</small></div></div><div class="metrics"><div class="surface"><small>Công việc tuần</small><strong>{{assignments.filter(a=>a.work_date>=weekStart&&a.work_date<=dateAt(weekStart,6)).length}}</strong></div><div class="surface"><small>Đã hoàn thành</small><strong>{{assignments.filter(a=>a.work_date>=weekStart&&a.work_date<=dateAt(weekStart,6)&&a.status==='done').length}}</strong></div></div></section>
   <section v-else-if="currentTab==='notifications'" key="notifications" class="content-panel"><div class="title-line"><div><span class="eyebrow">CẬP NHẬT CỦA BẠN</span><h1>Thông báo</h1><p>Yêu cầu đổi việc và thông tin nhóm.</p></div><button class="icon-button" @click="readNotifications" title="Đánh dấu đã đọc"><CheckCircle2 :size="20"/></button></div><div v-for="s in pendingSwaps" :key="s.id" class="surface swap-notice"><b><ArrowRightLeft :size="16"/> Yêu cầu nhận việc</b><p>{{nameOf(s.from_user)}} muốn đổi công việc {{choreOf(assignments.find(a=>a.id===s.assignment_id)?.chore_id)?.name}} cho bạn.</p><div class="row-buttons"><button class="btn btn-dark" @click="decideSwap(s,true)">Đồng ý</button><button class="btn btn-outline" @click="decideSwap(s,false)">Từ chối</button></div></div><div v-for="n in notifications" :key="n.id" class="notification-card" :class="{unread:!n.read_at}"><Bell :size="17"/><div><b>{{n.title}}</b><p>{{n.body}}</p><small>{{new Date(n.created_at).toLocaleString('vi-VN')}}</small></div></div><div v-if="!pendingSwaps.length&&!notifications.length" class="empty"><Bell :size="30"/><b>Chưa có thông báo</b></div></section>
   <section v-else-if="currentTab==='settings'" key="settings" class="content-panel"><div class="title-line"><div><span class="eyebrow">TÀI KHOẢN & ỨNG DỤNG</span><h1>Cài đặt</h1><p>Cá nhân hóa không gian Roomly của bạn.</p></div></div><div class="surface settings-list"><h3>Hồ sơ</h3><div class="settings-row"><span class="member-avatar">{{initials(user.id)}}</span><div><b>{{fullName}}</b><small>{{user.email}}</small></div><button class="icon-button" @click="draftName=fullName;modal='profile'"><Pencil :size="18"/></button></div></div><div class="surface settings-list"><h3>Nhóm của bạn</h3><div class="settings-row"><House :size="19"/><span>{{room.name}}</span><b>{{isOwner?'Trưởng nhóm':'Thành viên'}}</b></div><button v-if="isOwner" class="btn btn-outline" style="margin-top:14px" @click="roomDraft=room.name;modal='rename'">Đổi tên nhóm</button><button v-if="isOwner" class="btn btn-danger" style="margin-top:10px" @click="disbandRoom">Giải tán nhóm</button></div><button class="btn btn-outline" @click="logout"><LogOut :size="17"/> Đăng xuất</button></section>
   </Transition>
  </main>
  <nav class="bottom-nav" aria-label="Điều hướng chính"><button v-for="item in [{id:'schedule',icon:CalendarDays,label:'Lịch tuần'},{id:'members',icon:UsersRound,label:'Nhóm trọ'},{id:'chores',icon:ListTodo,label:'Công việc'},{id:'stats',icon:BarChart3,label:'Thống kê'}]" :key="item.id" @click="currentTab=item.id" :class="{active:currentTab===item.id}"><component :is="item.icon" :size="21"/><span>{{item.label}}</span></button></nav></div>
  <Transition name="modal"><div v-if="modal" class="modal-backdrop" @click.self="modal=''"><div class="modal-card" role="dialog" aria-modal="true"><header><h2>{{modal==='chore'?(draft.id?'Chỉnh sửa công việc':'Thêm công việc'):modal==='swap'?'Đổi người làm':modal==='profile'?'Chỉnh sửa hồ sơ':modal==='manual'?'Phân công thủ công':modal==='rename'?'Đổi tên nhóm':'Lưu ý phân lịch'}}</h2><button class="icon-button" aria-label="Đóng" @click="modal=''"><X :size="20"/></button></header><template v-if="modal==='chore'"><label>Tên công việc</label><input v-model="draft.name" placeholder="Ví dụ: Lau nhà" maxlength="80"/><label>Loại công việc</label><select v-model="draft.icon"><option value="sparkles">Khác</option><option value="lunch">Nấu trưa</option><option value="dinner">Nấu tối</option><option value="wash">Giặt đồ</option><option value="dry">Phơi đồ</option><option value="water">Đổi nước</option></select><div class="form-two"><div><label>Giờ thực hiện</label><input type="time" v-model="draft.start_time"/></div><div><label>Số phút</label><input type="number" v-model.number="draft.duration_minutes" min="5" max="360"/></div></div><label>Độ khó (điểm)</label><input type="number" v-model.number="draft.weight" min="1" max="10"/><label>Ngày lặp trong tuần</label><div class="day-options"><button v-for="(day,i) in weekdays" :key="i" type="button" :class="{selected:draft.weekdays.includes(i+1)}" @click="toggleWeekday(i+1)">{{day}}</button></div><label class="checkrow"><input type="checkbox" v-model="draft.enabled"/> Đang áp dụng</label><button class="btn btn-dark" :disabled="busy" @click="saveChore">Lưu công việc</button><button v-if="draft.id" class="btn btn-danger" @click="deleteChore(draft.id)">Xóa công việc</button></template><template v-else-if="modal==='swap'"><p>Yêu cầu một thành viên khác nhận việc này thay bạn. Người đó cần đồng ý.</p><label>Thành viên nhận việc</label><select v-model="newRecipient"><option value="">Chọn thành viên</option><option v-for="m in members.filter(m=>m.user_id!==user.id)" :key="m.user_id" :value="m.user_id">{{nameOf(m.user_id)}}</option></select><button class="btn btn-dark" :disabled="busy" @click="requestSwap">Gửi yêu cầu</button></template><template v-else-if="modal==='manual'"><p>Phân công việc ngày {{selectedDay.slice(8)}}/{{selectedDay.slice(5,7)}}. Hệ thống sẽ kiểm tra ngày rảnh và trùng giờ.</p><label>Công việc</label><select v-model="manualChore"><option value="">Chọn công việc</option><option v-for="c in chores.filter(x=>x.enabled)" :key="c.id" :value="c.id">{{c.name}} · {{formatClock(c.start_time)}}</option></select><label>Người thực hiện</label><select v-model="manualPerson"><option value="">Chọn thành viên</option><option v-for="m in members" :key="m.user_id" :value="m.user_id">{{nameOf(m.user_id)}}</option></select><button class="btn btn-dark" :disabled="busy" @click="saveManual">Lưu phân công</button></template><template v-else-if="modal==='rename'"><label>Tên nhóm</label><input v-model="roomDraft" maxlength="80"/><button class="btn btn-dark" :disabled="busy" @click="renameRoom">Lưu tên nhóm</button></template><template v-else-if="modal==='profile'"><label>Tên hiển thị</label><input v-model="draftName" maxlength="60"/><button class="btn btn-dark" :disabled="busy" @click="saveProfile">Lưu thay đổi</button></template><template v-else-if="modal==='warnings'"><p v-for="(w,i) in warnings" :key="i">{{w}}</p><button class="btn btn-dark" @click="modal=''">Đã hiểu</button></template></div></div></Transition>
 <Transition name="toast"><div v-if="error||message" class="toast-card" :class="{bad:error}"><AlertCircle v-if="error" :size="17"/><CheckCircle2 v-else :size="17"/> {{error||message}}</div></Transition>
</div>
</template>
