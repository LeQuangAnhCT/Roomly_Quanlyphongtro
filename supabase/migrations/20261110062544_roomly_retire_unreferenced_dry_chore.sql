-- Applied in Roomly Supabase production on 2026-11-10.
-- The previously separate "Phơi quần áo" template is now redundant.
-- Remove only if it is disabled and completely unreferenced, preserving any historical data.
delete from public.chores c
where c.icon='dry' and c.enabled=false
and not exists(select 1 from public.assignments a where a.chore_id=c.id)
and not exists(select 1 from public.chores next where next.depends_on=c.id);

