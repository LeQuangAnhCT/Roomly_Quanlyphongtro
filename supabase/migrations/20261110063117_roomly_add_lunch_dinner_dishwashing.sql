-- Applied to Supabase Roomly production on 2026-11-10.

-- Existing rooms: insert each dishwashing task once; preserve assignments.
insert into public.chores(room_id,name,icon,start_time,duration_minutes,weight,weekdays,time_mode,enabled)
select r.id,v.name,v.icon,v.start_time::time,30,1,array[1,2,3,4,5,6,7],'timed',true
from public.rooms r
cross join (values
 ('Rửa chén buổi trưa','dishes_lunch','12:00'),
 ('Rửa chén buổi tối','dishes_dinner','19:00')
) v(name,icon,start_time)
where not exists (
 select 1 from public.chores c
 where c.room_id=r.id and (c.icon=v.icon or lower(c.name)=lower(v.name))
);
-- New rooms: initialize dishwashing automatically with cooking, laundry and water.
create or replace function public.room_create(p_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_room uuid;
begin
 if auth.uid() is null then raise exception 'Login required';end if;
 if length(trim(coalesce(p_name,''))) not between 2 and 80 then raise exception 'Tên nhóm từ 2 đến 80 ký tự';end if;
 if exists(select 1 from public.room_members where user_id=auth.uid() and active)
 then raise exception 'Bạn đang thuộc nhóm trọ';end if;
 insert into public.rooms(name,owner_id) values(trim(p_name),auth.uid()) returning id into v_room;
 insert into public.room_members(room_id,user_id) values(v_room,auth.uid());
 insert into public.chores(room_id,name,icon,start_time,duration_minutes,weight,weekdays,time_mode) values
 (v_room,'Nấu ăn trưa','lunch','10:30',90,2,'{1,2,3,4,5,6,7}','timed'),
 (v_room,'Nấu ăn tối','dinner','17:00',90,2,'{1,2,3,4,5,6,7}','timed'),
 (v_room,'Rửa chén buổi trưa','dishes_lunch','12:00',30,1,'{1,2,3,4,5,6,7}','timed'),
 (v_room,'Rửa chén buổi tối','dishes_dinner','19:00',30,1,'{1,2,3,4,5,6,7}','timed'),
 (v_room,'Giặt và phơi quần áo','wash','08:00',105,2,'{1,3,5,7}','anytime'),
 (v_room,'Đổi bình nước','water','19:00',15,1,'{2,5}','anytime');
 return v_room;
end $$;
revoke all on function public.room_create(text) from public,anon;
grant execute on function public.room_create(text) to authenticated;

