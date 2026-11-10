-- Applied to Supabase Roomly production on 2026-11-10.
do $$
declare t text;
begin
 foreach t in array array['rooms','room_members','room_profiles','chores','assignments',
 'member_availability','room_busy_slots','room_work_debts','swap_requests','room_notifications']
 loop
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t)
  then execute format('alter publication supabase_realtime add table public.%I',t);
  end if;
 end loop;
end $$;
