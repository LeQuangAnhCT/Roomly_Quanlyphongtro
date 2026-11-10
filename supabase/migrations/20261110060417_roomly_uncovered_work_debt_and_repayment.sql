-- Applied on Roomly Supabase production; do not rerun directly.

create or replace function public.room_mark_uncovered(p_assignment uuid,p_reason text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.assignments%rowtype;c public.chores%rowtype;v_id uuid;
begin
 select * into a from public.assignments where id=p_assignment for update;
 if not found or a.assignee_id<>auth.uid() or not public.room_has_member(a.room_id)
 then raise exception 'Không được ghi nợ việc này';end if;
 if a.status<>'pending' or a.makeup_debt_id is not null then raise exception 'Công việc không thể ghi nợ';end if;
 if exists(select 1 from public.swap_requests where assignment_id=a.id and status='pending')
 then raise exception 'Chờ xử lý hoặc hủy yêu cầu chuyển việc trước khi ghi nợ';end if;
 select * into c from public.chores where id=a.chore_id;
 update public.assignments set status='skipped',notes=left(coalesce(p_reason,''),300) where id=a.id;
 insert into public.room_work_debts(room_id,user_id,source_assignment_id,chore_name,weight,reason)
 values(a.room_id,auth.uid(),a.id,c.name,c.weight,left(coalesce(p_reason,''),300))
 on conflict(source_assignment_id) do update set reason=excluded.reason returning id into v_id;
 insert into public.room_notifications(room_id,user_id,title,body)
 select a.room_id,r.owner_id,'Có công việc bị nợ',c.name||' chưa có người thay và đã ghi nợ.'
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
 if not found then raise exception 'Công việc bù không hợp lệ';end if;
 if p_date<= (now() at time zone 'Asia/Ho_Chi_Minh')::date then raise exception 'Chọn ngày tương lai để bù việc';end if;
 if not public.room_user_can_take(d.room_id,d.user_id,p_date,c.start_time,c.duration_minutes,null)
 then raise exception 'Thành viên đang bận vào giờ bù';end if;
 if exists(select 1 from public.assignments where chore_id=p_chore and work_date=p_date)
 then raise exception 'Công việc đã có người làm ngày này';end if;
 insert into public.assignments(room_id,chore_id,work_date,assignee_id,makeup_debt_id)
 values(d.room_id,p_chore,p_date,d.user_id,d.id) returning id into v_id;
 update public.room_work_debts set makeup_assignment_id=v_id where id=d.id;
 insert into public.room_notifications(room_id,user_id,title,body)
 values(d.room_id,d.user_id,'Lịch bù việc','Bạn được giao bù việc vào ngày '||p_date::text);
 return v_id;
end $$;

create or replace function public.room_complete_assignment(p_id uuid,p_done boolean) returns void
language plpgsql security definer set search_path='' as $$
declare a public.assignments%rowtype;
begin
 select * into a from public.assignments where id=p_id for update;
 if not found or a.assignee_id<>auth.uid() or not public.room_has_member(a.room_id) or a.status='skipped'
 then raise exception 'Bạn không được xác nhận việc này';end if;
 update public.assignments set status=case when p_done then 'done' else 'pending' end,
  completed_at=case when p_done then now() else null end where id=p_id;
 if a.makeup_debt_id is not null then
  update public.room_work_debts set status=case when p_done then 'settled' else 'owed' end,
   settled_at=case when p_done then now() else null end
   where id=a.makeup_debt_id and user_id=auth.uid();
 end if;
end $$;
revoke all on function public.room_mark_uncovered(uuid,text),public.room_schedule_makeup(uuid,uuid,date) from public,anon;
grant execute on function public.room_mark_uncovered(uuid,text),public.room_schedule_makeup(uuid,uuid,date) to authenticated;

