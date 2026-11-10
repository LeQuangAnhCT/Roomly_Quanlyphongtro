-- Applied to Roomly Supabase production on 2026-11-10.
CREATE OR REPLACE FUNCTION public.room_assign_manual(p_room uuid, p_chore uuid, p_date date, p_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;c public.chores%rowtype;a public.assignments%rowtype;
begin
 if not public.room_is_owner(p_room) then raise exception 'Chỉ trưởng nhóm được phân việc';end if;
 select * into c from public.chores where id=p_chore and room_id=p_room and enabled;
 if not found then raise exception 'Công việc không hợp lệ';end if;
 select * into a from public.assignments where chore_id=p_chore and work_date=p_date for update;
 if found and (a.status<>'pending' or a.makeup_debt_id is not null or a.rollover_source_id is not null)
 then raise exception 'Không sửa việc đã hoàn thành, nợ hoặc việc bù';end if;
 if not public.room_user_can_take(p_room,p_user,p_date,c.start_time,
   case when c.time_mode='anytime' then 0 else c.duration_minutes end,a.id)
 then raise exception 'Thành viên bận hoặc bị trùng giờ';end if;
 insert into public.assignments(room_id,chore_id,work_date,assignee_id)
 values(p_room,p_chore,p_date,p_user)
 on conflict(chore_id,work_date) do update set assignee_id=excluded.assignee_id,status='pending',completed_at=null
 returning id into v_id;
 return v_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.room_replace_week(p_room uuid, p_start date, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item jsonb; item2 jsonb;c public.chores%rowtype;c2 public.chores%rowtype;
 v_person uuid;v_date date;v_count int:=0;
begin
 if not public.room_is_owner(p_room) then raise exception 'Chỉ trưởng nhóm được phân lịch';end if;
 if extract(isodow from p_start)<>1 then raise exception 'Tuần phải bắt đầu từ thứ hai';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>100 then raise exception 'Lịch không hợp lệ';end if;
 if exists(select 1 from public.assignments x where x.room_id=p_room and x.work_date between p_start and p_start+6
 and (x.status<>'pending' or x.makeup_debt_id is not null or x.rollover_source_id is not null))
 then raise exception 'Tuần có công việc đã làm, nợ hoặc lịch bù nên không thể tạo lại';end if;
 for item in select value from jsonb_array_elements(p_rows) loop
  v_person=(item->>'assignee_id')::uuid;v_date=(item->>'work_date')::date;
  select * into c from public.chores x where x.id=(item->>'chore_id')::uuid and x.room_id=p_room and x.enabled;
  if not found or v_date not between p_start and p_start+6
   or not exists(select 1 from public.room_members m where m.room_id=p_room and m.user_id=v_person and m.active)
  then raise exception 'Công việc hoặc thành viên không hợp lệ';end if;
  if exists(select 1 from public.member_availability v where v.room_id=p_room and v.user_id=v_person and v.weekday=extract(isodow from v_date) and not v.available)
   or exists(select 1 from public.room_busy_slots b where b.room_id=p_room and b.user_id=v_person
   and (b.busy_date=v_date or b.weekday=extract(isodow from v_date))
   and (case when c.time_mode='anytime' then b.starts_at<=time '00:00' and b.ends_at>=time '23:59'
       else extract(epoch from b.starts_at)/60 < extract(epoch from c.start_time)/60+c.duration_minutes
       and extract(epoch from c.start_time)/60 < extract(epoch from b.ends_at)/60 end))
  then raise exception 'Lịch có thành viên đang bận';end if;
  for item2 in select value from jsonb_array_elements(p_rows) loop
   if item2->>'work_date'=item->>'work_date' and item2->>'assignee_id'=item->>'assignee_id' then
    select * into c2 from public.chores x where x.id=(item2->>'chore_id')::uuid;
    if c.id=c2.id and item2=item then continue;end if;
    if c.id=c2.id then raise exception 'Công việc phân lặp';end if;
    if c.time_mode='timed' and c2.time_mode='timed'
      and extract(epoch from c2.start_time)/60 < extract(epoch from c.start_time)/60+c.duration_minutes
      and extract(epoch from c.start_time)/60 < extract(epoch from c2.start_time)/60+c2.duration_minutes
    then raise exception 'Phân việc trùng giờ';end if;
   end if;
  end loop;
 end loop;
 delete from public.assignments x where x.room_id=p_room and x.work_date between p_start and p_start+6;
 for item in select value from jsonb_array_elements(p_rows) loop
  insert into public.assignments(room_id,chore_id,work_date,assignee_id)
  values(p_room,(item->>'chore_id')::uuid,(item->>'work_date')::date,(item->>'assignee_id')::uuid);
  v_count=v_count+1;
 end loop;
 return v_count;
end $function$
;
