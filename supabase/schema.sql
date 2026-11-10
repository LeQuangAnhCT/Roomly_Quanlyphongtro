-- ROOMLY initial schema. Dedicated Supabase project; never run against Shiftly.
create extension if not exists pgcrypto;
create table if not exists public.room_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '', avatar_url text,
  updated_at timestamptz not null default now()
);
create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(), name text not null check(length(trim(name)) between 2 and 80),
  invite_code text not null unique default upper(substr(encode(gen_random_bytes(12),'hex'),1,10)),
  owner_id uuid not null references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(), active boolean not null default true,
  primary key(room_id,user_id)
);
create table if not exists public.chores (
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.rooms(id) on delete cascade,
  name text not null check(length(trim(name)) between 2 and 80),icon text not null default 'sparkles',
  start_time time not null default '09:00',duration_minutes integer not null default 30 check(duration_minutes between 5 and 360),
  weight integer not null default 1 check(weight between 1 and 10),
  weekdays int[] not null default '{1,2,3,4,5,6,7}',
  depends_on uuid references public.chores(id) on delete set null,
  enabled boolean not null default true, created_at timestamptz not null default now(),
  unique(room_id,name)
);
create table if not exists public.member_availability (
  room_id uuid not null,user_id uuid not null,weekday integer not null check(weekday between 1 and 7),
  available boolean not null default true,
  primary key(room_id,user_id,weekday),
  foreign key(room_id,user_id) references public.room_members(room_id,user_id) on delete cascade
);
create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.rooms(id) on delete cascade,
  chore_id uuid not null references public.chores(id) on delete cascade,
  work_date date not null,assignee_id uuid not null references auth.users(id),
  status text not null default 'pending' check(status in ('pending','done','skipped')),
  completed_at timestamptz,notes text not null default '',
  created_at timestamptz not null default now(),
  unique(chore_id,work_date)
);
create table if not exists public.swap_requests (
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.rooms(id) on delete cascade,
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  from_user uuid not null references auth.users(id),to_user uuid not null references auth.users(id),
  status text not null default 'pending' check(status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),resolved_at timestamptz,
  check(from_user<>to_user)
);
create unique index if not exists swap_one_pending on public.swap_requests(assignment_id) where status='pending';
create table if not exists public.room_notifications (
  id uuid primary key default gen_random_uuid(),room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id),title text not null,body text not null default '',
  read_at timestamptz,created_at timestamptz not null default now()
);
create index if not exists idx_assignments_date on public.assignments(room_id,work_date);
create index if not exists idx_notifications_owner on public.room_notifications(user_id,created_at desc);

-- All membership helpers run as their owner, never use user-submitted IDs for identity.
create or replace function public.room_has_member(p_room uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.room_members m where m.room_id=p_room and m.user_id=(select auth.uid()) and m.active);
$$;
create or replace function public.room_is_owner(p_room uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.rooms r where r.id=p_room and r.owner_id=(select auth.uid()));
$$;
revoke all on function public.room_has_member(uuid),public.room_is_owner(uuid) from public,anon;
grant execute on function public.room_has_member(uuid),public.room_is_owner(uuid) to authenticated;

alter table public.room_profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.chores enable row level security;
alter table public.member_availability enable row level security;
alter table public.assignments enable row level security;
alter table public.swap_requests enable row level security;
alter table public.room_notifications enable row level security;

create policy "profiles read self or fellow member" on public.room_profiles for select to authenticated using (
  user_id=(select auth.uid()) or exists(select 1 from public.room_members mine join public.room_members theirs on theirs.room_id=mine.room_id and theirs.active where mine.user_id=(select auth.uid()) and mine.active and theirs.user_id=room_profiles.user_id)
);
create policy "profiles insert own" on public.room_profiles for insert to authenticated with check (user_id=(select auth.uid()));
create policy "profiles update own" on public.room_profiles for update to authenticated using (user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy "rooms read only members" on public.rooms for select to authenticated using (public.room_has_member(id));
create policy "room members read same room" on public.room_members for select to authenticated using (public.room_has_member(room_id));
create policy "chores read same room" on public.chores for select to authenticated using (public.room_has_member(room_id));
create policy "chores owner insert" on public.chores for insert to authenticated with check(public.room_is_owner(room_id));
create policy "chores owner update" on public.chores for update to authenticated using(public.room_is_owner(room_id)) with check(public.room_is_owner(room_id));
create policy "chores owner delete" on public.chores for delete to authenticated using(public.room_is_owner(room_id));
create policy "availability visible to room" on public.member_availability for select to authenticated using(public.room_has_member(room_id));
create policy "availability self insert" on public.member_availability for insert to authenticated with check(user_id=(select auth.uid()) and public.room_has_member(room_id));
create policy "availability self update" on public.member_availability for update to authenticated using(user_id=(select auth.uid()) and public.room_has_member(room_id)) with check(user_id=(select auth.uid()));
create policy "assignments visible same room" on public.assignments for select to authenticated using(public.room_has_member(room_id));
create policy "assignments owner insert" on public.assignments for insert to authenticated with check(public.room_is_owner(room_id) and exists(select 1 from public.chores c where c.id=chore_id and c.room_id=assignments.room_id) and exists(select 1 from public.room_members m where m.room_id=assignments.room_id and m.user_id=assignee_id and m.active));
create policy "assignments owner or assignee update" on public.assignments for update to authenticated using(public.room_is_owner(room_id) or (assignee_id=(select auth.uid()) and public.room_has_member(room_id))) with check(public.room_has_member(room_id));
create policy "assignments owner delete" on public.assignments for delete to authenticated using(public.room_is_owner(room_id));
create policy "swaps read participants and owner" on public.swap_requests for select to authenticated using(public.room_has_member(room_id) and (from_user=(select auth.uid()) or to_user=(select auth.uid()) or public.room_is_owner(room_id)));
create policy "swaps create own" on public.swap_requests for insert to authenticated with check(from_user=(select auth.uid()) and public.room_has_member(room_id) and exists(select 1 from public.assignments a where a.id=assignment_id and a.room_id=swap_requests.room_id and a.assignee_id=(select auth.uid()) and a.status='pending') and exists(select 1 from public.room_members m where m.room_id=swap_requests.room_id and m.user_id=to_user and m.active));
create policy "notifications read self" on public.room_notifications for select to authenticated using(user_id=(select auth.uid()));
create policy "notifications update self" on public.room_notifications for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));

-- One-room-per-account invariant, enforced by RPCs and database constraint.
create unique index if not exists one_active_room_per_user on public.room_members(user_id) where active;
create or replace function public.room_create(p_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_room uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'Tên nhóm từ 2 đến 80 ký tự'; end if;
 if exists(select 1 from public.room_members where user_id=auth.uid() and active) then raise exception 'Bạn đang thuộc một nhóm trọ'; end if;
 insert into public.rooms(name,owner_id) values(trim(p_name),auth.uid()) returning id into v_room;
 insert into public.room_members(room_id,user_id) values(v_room,auth.uid());
 insert into public.chores(room_id,name,icon,start_time,duration_minutes,weight,weekdays) values
 (v_room,'Nấu ăn trưa','cooking-pot','10:30',90,2,'{1,2,3,4,5,6,7}'),
 (v_room,'Nấu ăn tối','utensils','17:00',90,2,'{1,2,3,4,5,6,7}'),
 (v_room,'Giặt quần áo','washing-machine','08:00',60,1,'{1,3,5,7}'),
 (v_room,'Phơi quần áo','sun','09:15',30,1,'{1,3,5,7}'),
 (v_room,'Đổi bình nước','droplets','19:00',15,1,'{2,5}');
 return v_room;
end $$;
create or replace function public.room_join(p_code text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_room uuid;
begin
 if auth.uid() is null then raise exception 'Login required'; end if;
 if exists(select 1 from public.room_members where user_id=auth.uid() and active) then raise exception 'Bạn đang thuộc một nhóm trọ'; end if;
 select id into v_room from public.rooms where invite_code=upper(trim(p_code));
 if v_room is null then raise exception 'Mã mời không hợp lệ'; end if;
 insert into public.room_members(room_id,user_id) values(v_room,auth.uid()) on conflict(room_id,user_id) do update set active=true;
 return v_room;
end $$;
create or replace function public.room_leave(p_room uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.room_has_member(p_room) then raise exception 'Not a member'; end if;
 if public.room_is_owner(p_room) then raise exception 'Trưởng nhóm phải giải tán nhóm hoặc chuyển quyền trước khi rời'; end if;
 update public.room_members set active=false where room_id=p_room and user_id=auth.uid();
end $$;
create or replace function public.room_remove_member(p_room uuid,p_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.room_is_owner(p_room) then raise exception 'Trưởng nhóm mới được xóa thành viên'; end if;
 if p_user=auth.uid() then raise exception 'Không thể xóa trưởng nhóm'; end if;
 update public.room_members set active=false where room_id=p_room and user_id=p_user;
end $$;
-- Use a privileged transactional RPC for status-only update: assignees must never reassign ownership.
create or replace function public.room_complete_assignment(p_id uuid,p_done boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 update public.assignments set status=case when p_done then 'done' else 'pending' end,completed_at=case when p_done then now() else null end
 where id=p_id and assignee_id=auth.uid() and public.room_has_member(room_id);
 if not found then raise exception 'Bạn không được xác nhận việc này'; end if;
end $$;
create or replace function public.room_resolve_swap(p_id uuid,p_accept boolean) returns void
language plpgsql security definer set search_path='' as $$
declare s public.swap_requests%rowtype;
begin
 select * into s from public.swap_requests where id=p_id for update;
 if not found or s.status<>'pending' or s.to_user<>auth.uid() or not public.room_has_member(s.room_id) then raise exception 'Không có quyền xử lý'; end if;
 if p_accept then
   update public.assignments set assignee_id=s.to_user where id=s.assignment_id and assignee_id=s.from_user and status='pending';
   if not found then raise exception 'Công việc đã thay đổi'; end if;
 end if;
 update public.swap_requests set status=case when p_accept then 'accepted' else 'declined' end,resolved_at=now() where id=p_id;
end $$;

-- Revoke table-level UPDATE of assignments (RLS alone cannot limit column changes).
revoke update on public.assignments from authenticated;
-- Only authenticated API clients may execute expected RPC operations.
do $$ declare r record; begin for r in select oid::regprocedure sig from pg_proc where pronamespace='public'::regnamespace and proname like 'room_%' loop execute format('revoke all on function %s from public,anon',r.sig);execute format('grant execute on function %s to authenticated',r.sig);end loop; end $$;
-- Harden invite data: plain authenticated users do not have table INSERT access.

-- Schedule generation is atomic and constrained to an exactly seven-day period.
create or replace function public.room_replace_week(p_room uuid,p_start date,p_rows jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare item jsonb; v_chore uuid; v_person uuid; v_date date; v_count integer:=0;
begin
 if not public.room_is_owner(p_room) then raise exception 'Chỉ trưởng nhóm được phân lịch'; end if;
 if extract(isodow from p_start)<>1 then raise exception 'Lịch phải bắt đầu thứ hai'; end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>100 then raise exception 'Dữ liệu lịch không hợp lệ'; end if;
 if exists(select 1 from public.assignments where room_id=p_room and work_date between p_start and p_start+6 and status='done') then raise exception 'Không thể ghi đè lịch đã hoàn thành'; end if;
 -- Validate full payload BEFORE removing existing week.
 for item in select value from jsonb_array_elements(p_rows) loop
   v_chore:=(item->>'chore_id')::uuid;v_person:=(item->>'assignee_id')::uuid;v_date:=(item->>'work_date')::date;
   if v_date not between p_start and p_start+6
     or not exists(select 1 from public.chores where id=v_chore and room_id=p_room and enabled)
     or not exists(select 1 from public.room_members where room_id=p_room and user_id=v_person and active)
   then raise exception 'Lịch có công việc hoặc thành viên không hợp lệ'; end if;
 end loop;
 delete from public.assignments where room_id=p_room and work_date between p_start and p_start+6;
 for item in select value from jsonb_array_elements(p_rows) loop
   insert into public.assignments(room_id,chore_id,work_date,assignee_id)
   values(p_room,(item->>'chore_id')::uuid,(item->>'work_date')::date,(item->>'assignee_id')::uuid);
   v_count:=v_count+1;
 end loop;
 return v_count;
end $$;

-- New swap requests and accepted changes create recipient-only notifications.
create or replace function public.room_swap_notify() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then
   insert into public.room_notifications(room_id,user_id,title,body)
   values(new.room_id,new.to_user,'Yêu cầu đổi việc','Một thành viên muốn chuyển công việc cho bạn.');
 elsif TG_OP='UPDATE' and old.status='pending' and new.status<>'pending' then
   insert into public.room_notifications(room_id,user_id,title,body)
   values(new.room_id,new.from_user,'Kết quả đổi việc',case when new.status='accepted' then 'Yêu cầu đổi việc đã được đồng ý.' else 'Yêu cầu đổi việc đã bị từ chối.' end);
 end if;
 return new;
end $$;
drop trigger if exists tr_room_swap_notify on public.swap_requests;
create trigger tr_room_swap_notify after insert or update of status on public.swap_requests
 for each row execute function public.room_swap_notify();
revoke all on function public.room_swap_notify() from public,anon,authenticated;
revoke all on function public.room_replace_week(uuid,date,jsonb) from public,anon;
grant execute on function public.room_replace_week(uuid,date,jsonb) to authenticated;

-- A room member can NEVER directly change another assignee via API UPDATE.
-- All assignment status updates go through room_complete_assignment.
-- Keep all privileges constrained to the narrow RLS policies above.

-- Additional owner-only actions (applied separately on the dedicated Roomly project).
create or replace function public.room_assign_manual(p_room uuid,p_chore uuid,p_date date,p_user uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_time time;v_minutes integer;v_wd integer;
begin
 if not public.room_is_owner(p_room) then raise exception 'Chỉ trưởng nhóm được phân việc';end if;
 select start_time,duration_minutes into v_time,v_minutes from public.chores where id=p_chore and room_id=p_room and enabled;
 if not found then raise exception 'Công việc không hợp lệ';end if;
 if not exists(select 1 from public.room_members where room_id=p_room and user_id=p_user and active) then raise exception 'Người được giao không thuộc nhóm';end if;
 v_wd:=extract(isodow from p_date);
 if exists(select 1 from public.member_availability where room_id=p_room and user_id=p_user and weekday=v_wd and not available) then raise exception 'Người này không rảnh ngày đã chọn';end if;
 if exists(select 1 from public.assignments a join public.chores c on c.id=a.chore_id
   where a.room_id=p_room and a.work_date=p_date and a.assignee_id=p_user and a.chore_id<>p_chore
    and extract(epoch from c.start_time)/60 < extract(epoch from v_time)/60+v_minutes
    and extract(epoch from v_time)/60 < extract(epoch from c.start_time)/60+c.duration_minutes)
 then raise exception 'Thành viên bị trùng giờ công việc';end if;
 if exists(select 1 from public.assignments where room_id=p_room and chore_id=p_chore and work_date=p_date and status='done') then raise exception 'Không thể thay đổi việc đã hoàn thành';end if;
 insert into public.assignments(room_id,chore_id,work_date,assignee_id)
 values(p_room,p_chore,p_date,p_user)
 on conflict(chore_id,work_date) do update set assignee_id=excluded.assignee_id,status='pending',completed_at=null returning id into v_id;
 return v_id;
end $$;
create or replace function public.room_rename(p_room uuid,p_name text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.room_is_owner(p_room) or length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'Không được đổi tên nhóm';end if;
 update public.rooms set name=trim(p_name) where id=p_room;
end $$;
create or replace function public.room_disband(p_room uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.room_is_owner(p_room) then raise exception 'Chỉ trưởng nhóm được giải tán';end if;
 delete from public.rooms where id=p_room;
end $$;
revoke all on function public.room_assign_manual(uuid,uuid,date,uuid),public.room_rename(uuid,text),public.room_disband(uuid) from public,anon;
grant execute on function public.room_assign_manual(uuid,uuid,date,uuid),public.room_rename(uuid,text),public.room_disband(uuid) to authenticated;
