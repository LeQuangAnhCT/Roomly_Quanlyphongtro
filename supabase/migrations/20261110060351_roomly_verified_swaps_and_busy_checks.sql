-- Applied on Roomly Supabase production; do not rerun directly.

create or replace function public.room_user_can_take(p_room uuid,p_user uuid,p_date date,p_start time,p_minutes int,p_exclude uuid default null)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.room_members m where m.room_id=p_room and m.user_id=p_user and m.active)
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
revoke all on function public.room_user_can_take(uuid,uuid,date,time,integer,uuid) from public,anon;
grant execute on function public.room_user_can_take(uuid,uuid,date,time,integer,uuid) to authenticated;
drop policy if exists swaps_create on public.swap_requests;
create policy swaps_create on public.swap_requests for insert to authenticated with check(
 from_user=auth.uid() and public.room_has_member(swap_requests.room_id)
 and exists(select 1 from public.assignments a join public.chores c on c.id=a.chore_id
  where a.id=swap_requests.assignment_id and a.room_id=swap_requests.room_id
  and a.assignee_id=auth.uid() and a.status='pending'
  and public.room_user_can_take(swap_requests.room_id,swap_requests.to_user,a.work_date,c.start_time,c.duration_minutes,a.id))
);
create or replace function public.room_resolve_swap(p_id uuid,p_accept boolean) returns void
language plpgsql security definer set search_path='' as $$
declare s public.swap_requests%rowtype;a public.assignments%rowtype;c public.chores%rowtype;
begin
 select * into s from public.swap_requests where id=p_id for update;
 if not found or s.status<>'pending' or s.to_user<>auth.uid() or not public.room_has_member(s.room_id)
 then raise exception 'Không được xử lý yêu cầu này';end if;
 select * into a from public.assignments where id=s.assignment_id for update;
 if not found or a.room_id<>s.room_id or a.assignee_id<>s.from_user or a.status<>'pending'
 then raise exception 'Công việc đã được thay đổi';end if;
 if p_accept then
  select * into c from public.chores where id=a.chore_id;
  if not public.room_user_can_take(a.room_id,s.to_user,a.work_date,c.start_time,c.duration_minutes,a.id)
  then raise exception 'Người nhận đã có lịch bận hoặc trùng giờ';end if;
  update public.assignments set assignee_id=s.to_user where id=a.id;
 end if;
 update public.swap_requests set status=case when p_accept then 'accepted' else 'declined' end,resolved_at=now() where id=p_id;
end $$;

