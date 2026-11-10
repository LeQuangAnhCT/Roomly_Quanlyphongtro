-- Applied on Roomly Supabase production; do not rerun directly.

create table if not exists public.room_busy_slots(
 id uuid primary key default gen_random_uuid(),room_id uuid not null,user_id uuid not null,
 weekday integer check(weekday between 1 and 7),busy_date date,
 starts_at time not null,ends_at time not null,
 reason text not null default 'Bận',created_at timestamptz not null default now(),
 foreign key(room_id,user_id) references public.room_members(room_id,user_id) on delete cascade,
 constraint busy_day_choice check((weekday is null)<>(busy_date is null)),
 constraint busy_time_check check(ends_at>starts_at),
 constraint busy_reason_check check(char_length(reason) between 1 and 120)
);
create index if not exists room_busy_lookup on public.room_busy_slots(room_id,user_id,weekday,busy_date);
alter table public.room_busy_slots enable row level security;
create policy busy_select on public.room_busy_slots for select to authenticated using(public.room_has_member(room_id));
create policy busy_insert on public.room_busy_slots for insert to authenticated with check(user_id=auth.uid() and public.room_has_member(room_id));
create policy busy_update on public.room_busy_slots for update to authenticated using(user_id=auth.uid() and public.room_has_member(room_id)) with check(user_id=auth.uid() and public.room_has_member(room_id));
create policy busy_delete on public.room_busy_slots for delete to authenticated using(user_id=auth.uid() and public.room_has_member(room_id));
revoke update on public.room_busy_slots from authenticated;
grant update(weekday,busy_date,starts_at,ends_at,reason) on public.room_busy_slots to authenticated;
create table if not exists public.room_work_debts(
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms(id) on delete cascade,
 user_id uuid not null references auth.users(id),
 source_assignment_id uuid unique references public.assignments(id) on delete set null,
 makeup_assignment_id uuid unique references public.assignments(id) on delete set null,
 chore_name text not null,weight int not null check(weight between 1 and 10),
 reason text not null default '',status text not null default 'owed' check(status in ('owed','settled')),
 created_at timestamptz not null default now(),settled_at timestamptz
);
create index if not exists room_debts_by_user on public.room_work_debts(room_id,user_id,status);
alter table public.room_work_debts enable row level security;
create policy debts_select on public.room_work_debts for select to authenticated using(public.room_has_member(room_id));
revoke insert,update,delete on public.room_work_debts from anon,authenticated;
alter table public.assignments add column if not exists makeup_debt_id uuid unique references public.room_work_debts(id) on delete set null;

