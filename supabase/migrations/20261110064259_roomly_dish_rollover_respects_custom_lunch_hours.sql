-- Applied to Roomly Supabase production on 2026-11-10.
CREATE OR REPLACE FUNCTION public.room_rollover_dishes(p_room uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_today date := (now() at time zone 'Asia/Ho_Chi_Minh')::date;
 v_source public.assignments%rowtype;
 v_target public.assignments%rowtype;
 v_lunch uuid;
 v_lunch_start time;
 v_lunch_minutes integer;
 v_date date;
 v_moved int := 0;
 v_day int;
 v_done boolean;
begin
 if auth.uid() is null or not public.room_has_member(p_room) then
  raise exception 'Không có quyền cập nhật nhóm';
 end if;
 perform pg_advisory_xact_lock(hashtext(p_room::text),42157);
 select c.id,c.start_time,c.duration_minutes into v_lunch,v_lunch_start,v_lunch_minutes from public.chores c
 where c.room_id=p_room and c.icon='dishes_lunch' and c.enabled
 order by c.created_at limit 1;
 if v_lunch is null then return 0;end if;
 -- Only actual scheduled unfinished dishwashing is carried forward.
 -- A maximum of 30 future days are scanned per source, so no entries are silently lost.
 for v_source in
  select a.* from public.assignments a join public.chores c on c.id=a.chore_id
  where a.room_id=p_room and c.icon in ('dishes_lunch','dishes_dinner')
    and a.status='pending' and a.work_date<v_today
    and a.makeup_debt_id is null
  order by a.work_date,c.start_time desc,a.created_at for update of a
 loop
  v_done:=false;
  for v_day in 0..29 loop
   v_date:=greatest(v_today,v_source.work_date+1)+v_day;
   -- Do not overwrite an already completed lunch or a lunch already carrying another backlog.
   select * into v_target from public.assignments a
   where a.chore_id=v_lunch and a.work_date=v_date for update;
   if found and (v_target.status<>'pending' or v_target.rollover_source_id is not null
      or v_target.makeup_debt_id is not null) then continue;end if;
   -- Keep original responsible member if that person's timetable allows lunch.
   if not public.room_user_can_take(p_room,v_source.assignee_id,v_date,v_lunch_start,v_lunch_minutes,v_target.id)
   then continue;end if;
   if v_target.id is null then
    insert into public.assignments(room_id,chore_id,work_date,assignee_id,rollover_source_id,notes)
    values(p_room,v_lunch,v_date,v_source.assignee_id,v_source.id,
      'Rửa chén chưa làm ngày '||v_source.work_date::text||' — chuyển sang buổi trưa')
    returning * into v_target;
   else
    update public.assignments a
    set assignee_id=v_source.assignee_id,rollover_source_id=v_source.id,
      notes='Rửa chén chưa làm ngày '||v_source.work_date::text||' — thay lượt rửa chén trưa',
      completed_at=null
    where a.id=v_target.id;
   end if;
   update public.assignments a
   set status='skipped',notes='Đã chuyển sang trưa ngày '||v_date::text
   where a.id=v_source.id;
   insert into public.room_notifications(room_id,user_id,title,body)
   values(p_room,v_source.assignee_id,'Rửa chén chuyển sang buổi trưa',
    'Lượt rửa chén chưa làm ngày '||v_source.work_date::text||
    ' được chuyển sang trưa ngày '||v_date::text);
   v_moved:=v_moved+1;
   v_done:=true;
   exit;
  end loop;
  -- If no free slot is found, keep the pending source untouched and visible.
 end loop;
 return v_moved;
end $function$
;
