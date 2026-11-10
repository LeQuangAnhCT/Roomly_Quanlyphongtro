-- Applied in Roomly Supabase production on 2026-11-10.

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
  if not public.room_user_can_take(a.room_id,s.to_user,a.work_date,c.start_time,
   case when c.time_mode='anytime' then 0 else c.duration_minutes end,a.id)
  then raise exception 'Người nhận bận hoặc trùng giờ';end if;
  update public.assignments set assignee_id=s.to_user where id=a.id;
 end if;
 update public.swap_requests set status=case when p_accept then 'accepted' else 'declined' end,resolved_at=now() where id=p_id;
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
 if p_date<=(now() at time zone 'Asia/Ho_Chi_Minh')::date then raise exception 'Chọn ngày tương lai để bù';end if;
 if not public.room_user_can_take(d.room_id,d.user_id,p_date,c.start_time,
   case when c.time_mode='anytime' then 0 else c.duration_minutes end,null)
 then raise exception 'Thành viên bận vào ngày bù';end if;
 if exists(select 1 from public.assignments where chore_id=p_chore and work_date=p_date)
 then raise exception 'Công việc đã có người làm ngày này';end if;
 insert into public.assignments(room_id,chore_id,work_date,assignee_id,makeup_debt_id)
 values(d.room_id,p_chore,p_date,d.user_id,d.id) returning id into v_id;
 update public.room_work_debts set makeup_assignment_id=v_id where id=d.id;
 insert into public.room_notifications(room_id,user_id,title,body)
 values(d.room_id,d.user_id,'Lịch bù việc','Bạn được giao bù việc vào ngày '||p_date::text);
 return v_id;
end $$;
drop policy if exists swaps_create on public.swap_requests;
create policy swaps_create on public.swap_requests for insert to authenticated with check(
 from_user=auth.uid() and public.room_has_member(swap_requests.room_id)
 and exists(select 1 from public.assignments a join public.chores c on c.id=a.chore_id
  where a.id=swap_requests.assignment_id and a.room_id=swap_requests.room_id
   and a.assignee_id=auth.uid() and a.status='pending' and a.makeup_debt_id is null
   and public.room_user_can_take(swap_requests.room_id,swap_requests.to_user,a.work_date,c.start_time,
      case when c.time_mode='anytime' then 0 else c.duration_minutes end,a.id))
);
create or replace function public.room_create(p_name text) returns uuid language plpgsql security definer set search_path='' as $$
declare v_room uuid;
begin
 if auth.uid() is null then raise exception 'Login required';end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'Tên nhóm từ 2 đến 80 ký tự';end if;
 if exists(select 1 from public.room_members where user_id=auth.uid() and active) then raise exception 'Bạn đang thuộc nhóm trọ';end if;
 insert into public.rooms(name,owner_id) values(trim(p_name),auth.uid()) returning id into v_room;
 insert into public.room_members(room_id,user_id) values(v_room,auth.uid());
 insert into public.chores(room_id,name,icon,start_time,duration_minutes,weight,weekdays,time_mode) values
 (v_room,'Nấu ăn trưa','lunch','10:30',90,2,'{1,2,3,4,5,6,7}','timed'),
 (v_room,'Nấu ăn tối','dinner','17:00',90,2,'{1,2,3,4,5,6,7}','timed'),
 (v_room,'Giặt và phơi quần áo','wash','08:00',105,2,'{1,3,5,7}','anytime'),
 (v_room,'Đổi bình nước','water','19:00',15,1,'{2,5}','anytime');
 return v_room;
end $$;

