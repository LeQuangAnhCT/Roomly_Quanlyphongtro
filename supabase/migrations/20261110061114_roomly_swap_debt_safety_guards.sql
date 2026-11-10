-- Applied on Roomly Supabase production; do not rerun directly.

create or replace function public.room_user_can_take(p_room uuid,p_user uuid,p_date date,p_start time,p_minutes int,p_exclude uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select public.room_has_member(p_room)
 and exists(select 1 from public.room_members m where m.room_id=p_room and m.user_id=p_user and m.active)
 and not exists(select 1 from public.member_availability v where v.room_id=p_room and v.user_id=p_user and v.weekday=extract(isodow from p_date) and not v.available)
 and not exists(select 1 from public.room_busy_slots b where b.room_id=p_room and b.user_id=p_user
 and (b.weekday=extract(isodow from p_date) or b.busy_date=p_date)
 and extract(epoch from b.starts_at)/60 < extract(epoch from p_start)/60+p_minutes
 and extract(epoch from p_start)/60 < extract(epoch from b.ends_at)/60)
 and not exists(select 1 from public.assignments a join public.chores c on c.id=a.chore_id
 where a.room_id=p_room and a.work_date=p_date and a.assignee_id=p_user
 and a.id is distinct from p_exclude and a.status<>'skipped'
 and extract(epoch from c.start_time)/60 < extract(epoch from p_start)/60+p_minutes
 and extract(epoch from p_start)/60 < extract(epoch from c.start_time)/60+c.duration_minutes);
$$;
drop policy if exists swaps_create on public.swap_requests;
create policy swaps_create on public.swap_requests for insert to authenticated with check(
 from_user=auth.uid() and public.room_has_member(swap_requests.room_id)
 and exists(select 1 from public.assignments a join public.chores c on c.id=a.chore_id
 where a.id=swap_requests.assignment_id and a.room_id=swap_requests.room_id
 and a.assignee_id=auth.uid() and a.status='pending' and a.makeup_debt_id is null
 and public.room_user_can_take(swap_requests.room_id,swap_requests.to_user,a.work_date,c.start_time,c.duration_minutes,a.id))
);
create or replace function public.room_resolve_swap(p_id uuid,p_accept boolean) returns void
language plpgsql security definer set search_path='' as $$
declare s public.swap_requests%rowtype;a public.assignments%rowtype;c public.chores%rowtype;
begin
 select * into s from public.swap_requests where id=p_id for update;
 if not found or s.status<>'pending' or s.to_user<>auth.uid() or not public.room_has_member(s.room_id)
 then raise exception 'Không được xử lý yêu cầu';end if;
 select * into a from public.assignments where id=s.assignment_id for update;
 if not found or a.room_id<>s.room_id or a.assignee_id<>s.from_user or a.status<>'pending' or a.makeup_debt_id is not null
 then raise exception 'Công việc đã thay đổi hoặc là việc bù nợ';end if;
 if p_accept then
  select * into c from public.chores where id=a.chore_id;
  if not public.room_user_can_take(a.room_id,s.to_user,a.work_date,c.start_time,c.duration_minutes,a.id)
  then raise exception 'Người nhận đã có lịch bận hoặc trùng giờ';end if;
  update public.assignments set assignee_id=s.to_user where id=a.id;
 end if;
 update public.swap_requests set status=case when p_accept then 'accepted' else 'declined' end,resolved_at=now() where id=p_id;
end $$;
create or replace function public.room_mark_uncovered(p_assignment uuid,p_reason text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assignments%rowtype;c public.chores%rowtype;v_id uuid;
begin
 select * into a from public.assignments where id=p_assignment for update;
 if not found or a.assignee_id<>auth.uid() or not public.room_has_member(a.room_id)
 then raise exception 'Không được ghi nợ việc này';end if;
 if a.status<>'pending' or a.makeup_debt_id is not null then raise exception 'Công việc không thể ghi nợ';end if;
 -- Cancels outstanding invitations atomically when nobody can cover the task.
 update public.swap_requests set status='cancelled',resolved_at=now()
 where assignment_id=a.id and status='pending';
 select * into c from public.chores where id=a.chore_id;
 update public.assignments set status='skipped',notes=left(coalesce(p_reason,''),300) where id=a.id;
 insert into public.room_work_debts(room_id,user_id,source_assignment_id,chore_name,weight,reason)
 values(a.room_id,auth.uid(),a.id,c.name,c.weight,left(coalesce(p_reason,''),300))
 on conflict(source_assignment_id) do update set reason=excluded.reason returning id into v_id;
 insert into public.room_notifications(room_id,user_id,title,body)
 select a.room_id,r.owner_id,'Có công việc bị nợ',c.name||' chưa có người nhận và đã ghi nợ.'
 from public.rooms r where r.id=a.room_id and r.owner_id<>auth.uid();
 return v_id;
end $$;
create or replace function public.room_schedule_makeup(p_debt uuid,p_chore uuid,p_date date)
returns uuid language plpgsql security definer set search_path='' as $$
declare d public.room_work_debts%rowtype;c public.chores%rowtype;v_id uuid;
begin
 select * into d from public.room_work_debts where id=p_debt for update;
 if not found or not public.room_is_owner(d.room_id) or d.status<>'owed' or d.makeup_assignment_id is not null
 then raise exception 'Không thể phân bù khoản nợ';end if;
 select * into c from public.chores where id=p_chore and room_id=d.room_id and enabled;
 if not found or c.weight<d.weight then raise exception 'Việc bù phải có điểm bằng hoặc cao hơn khoản nợ';end if;
 if p_date <= (now() at time zone 'Asia/Ho_Chi_Minh')::date then raise exception 'Chọn ngày tương lai để bù';end if;
 if not public.room_user_can_take(d.room_id,d.user_id,p_date,c.start_time,c.duration_minutes,null)
 then raise exception 'Thành viên bận vào thời gian bù';end if;
 if exists(select 1 from public.assignments where chore_id=p_chore and work_date=p_date)
 then raise exception 'Công việc đã có người làm ngày này';end if;
 insert into public.assignments(room_id,chore_id,work_date,assignee_id,makeup_debt_id)
 values(d.room_id,p_chore,p_date,d.user_id,d.id) returning id into v_id;
 update public.room_work_debts set makeup_assignment_id=v_id where id=d.id;
 insert into public.room_notifications(room_id,user_id,title,body)
 values(d.room_id,d.user_id,'Lịch bù việc','Bạn được giao bù việc vào ngày '||p_date::text);
 return v_id;
end $$;
create or replace function public.room_swap_notify() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
  insert into public.room_notifications(room_id,user_id,title,body)
  values(new.room_id,new.to_user,'Yêu cầu nhận việc','Thành viên muốn bạn nhận thay công việc này.');
 elsif TG_OP='UPDATE' and old.status='pending' and new.status<>'pending' then
  insert into public.room_notifications(room_id,user_id,title,body)
  values(new.room_id,new.from_user,'Kết quả chuyển việc',
    case new.status when 'accepted' then 'Đã có người nhận giúp.'
    when 'cancelled' then 'Yêu cầu chuyển việc đã được hủy.'
    else 'Thành viên đã từ chối nhận việc.' end);
  if new.status='cancelled' then
   insert into public.room_notifications(room_id,user_id,title,body)
   values(new.room_id,new.to_user,'Yêu cầu đã hủy','Bạn không cần nhận công việc này nữa.');
  end if;
 end if;
 return new;
end $$;

