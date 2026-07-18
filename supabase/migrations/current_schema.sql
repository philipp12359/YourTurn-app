-- YourTurn current Supabase schema snapshot
-- Generated from the live project on 2026-07-17.
-- Secret values and app_assets row contents are intentionally not included.

create extension if not exists pgcrypto;

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null check (char_length(name) between 1 and 60),
  created_by uuid references auth.users(id) on delete set null,
  starts_on date default current_date,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 30),
  joined_at timestamptz not null default now(),
  unique (trip_id, user_id)
);

create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  storage_path text not null,
  is_anchor boolean not null default false,
  taken_on date not null default current_date,
  created_at timestamptz not null default now()
);

create table if not exists public.turns (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  turn_date date not null default current_date,
  status text not null default 'pending' check (status in ('pending','completed','skipped')),
  photo_id uuid references public.photos(id) on delete set null,
  notified_at timestamptz,
  unique (trip_id, turn_date)
);

create table if not exists public.likes (
  photo_id uuid not null references public.photos(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (photo_id, member_id)
);

create table if not exists public.turn_passes (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  turn_id uuid not null references public.turns(id) on delete cascade,
  passed_by_member_id uuid not null references public.members(id) on delete cascade,
  passed_to_member_id uuid not null references public.members(id) on delete cascade,
  passed_at timestamptz not null default now()
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  last_error text,
  failed_at timestamptz,
  unique (member_id, endpoint)
);

create table if not exists public.main_photo_captions (
  photo_id uuid primary key references public.photos(id) on delete cascade,
  trip_id uuid not null references public.trips(id) on delete cascade,
  caption text not null check (char_length(btrim(caption)) between 1 and 160),
  updated_by_member_id uuid references public.members(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Internal app-delivery tables. No production data or secrets are committed.
create table if not exists public.app_assets (
  asset_key text primary key,
  html text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.private_config (
  key text primary key,
  value text not null
);

alter table public.trips enable row level security;
alter table public.members enable row level security;
alter table public.photos enable row level security;
alter table public.turns enable row level security;
alter table public.likes enable row level security;
alter table public.turn_passes enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.main_photo_captions enable row level security;
alter table public.app_assets enable row level security;
alter table public.private_config enable row level security;

create or replace function public.is_trip_member(p_trip uuid)
returns boolean
language sql
stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.members
    where trip_id = p_trip and user_id = auth.uid()
  );
$$;

create or replace function public.peek_trip(p_slug text)
returns json
language sql
stable security definer
set search_path = public
as $$
  select json_build_object(
    'name', t.name,
    'slug', t.slug,
    'member_count', (select count(*) from public.members m where m.trip_id = t.id),
    'photo_count', (select count(*) from public.photos p where p.trip_id = t.id)
  )
  from public.trips t where t.slug = p_slug;
$$;

create or replace function public.join_trip(p_slug text, p_display_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip public.trips;
  v_member public.members;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into v_trip from public.trips where slug = p_slug;
  if v_trip.id is null then raise exception 'trip not found'; end if;

  insert into public.members (trip_id, user_id, display_name)
  values (v_trip.id, auth.uid(), p_display_name)
  on conflict (trip_id, user_id)
    do update set display_name = excluded.display_name
  returning * into v_member;

  return json_build_object('trip', row_to_json(v_trip), 'member', row_to_json(v_member));
end;
$$;

create or replace function public.create_trip(p_name text, p_display_name text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug text;
  v_trip public.trips;
  v_member public.members;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug);
  v_slug := left(v_slug, 14) || '-' || substr(md5(random()::text), 1, 4);

  insert into public.trips (slug, name, created_by)
  values (v_slug, p_name, auth.uid())
  returning * into v_trip;

  insert into public.members (trip_id, user_id, display_name)
  values (v_trip.id, auth.uid(), p_display_name)
  returning * into v_member;

  insert into public.turns (trip_id, member_id, turn_date)
  values (v_trip.id, v_member.id, current_date);

  return json_build_object('trip', row_to_json(v_trip), 'member', row_to_json(v_member));
end;
$$;

create or replace function public.complete_turn(p_turn_id uuid, p_photo_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turn public.turns;
  v_next_member public.members;
begin
  select t.* into v_turn
  from public.turns t
  join public.members m on m.id = t.member_id
  where t.id = p_turn_id and m.user_id = auth.uid() and t.status = 'pending';
  if v_turn.id is null then raise exception 'not your pending turn'; end if;

  update public.photos set is_anchor = true where id = p_photo_id and trip_id = v_turn.trip_id;
  update public.turns set status = 'completed', photo_id = p_photo_id where id = v_turn.id;

  select m.* into v_next_member
  from public.members m
  where m.trip_id = v_turn.trip_id
  order by (
    select max(t2.turn_date) from public.turns t2 where t2.member_id = m.id
  ) asc nulls first, random()
  limit 1;

  insert into public.turns (trip_id, member_id, turn_date)
  values (v_turn.trip_id, v_next_member.id, current_date + 1)
  on conflict (trip_id, turn_date) do nothing;

  return json_build_object('completed', v_turn.id, 'next_member', row_to_json(v_next_member));
end;
$$;

create or replace function public.pass_turn(p_turn_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turn public.turns;
  v_next_member public.members;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select t.* into v_turn
  from public.turns t
  join public.members m on m.id = t.member_id
  where t.id = p_turn_id
    and m.user_id = auth.uid()
    and t.status = 'pending'
  for update of t;

  if v_turn.id is null then raise exception 'not your pending turn'; end if;

  select m.* into v_next_member
  from public.members m
  where m.trip_id = v_turn.trip_id
    and m.id <> v_turn.member_id
    and not exists (
      select 1 from public.turn_passes tp
      where tp.turn_id = v_turn.id
        and tp.passed_by_member_id = m.id
    )
  order by (
    select max(t2.turn_date)
    from public.turns t2
    where t2.member_id = m.id and t2.id <> v_turn.id
  ) asc nulls first, random()
  limit 1;

  if v_next_member.id is null then
    raise exception 'no one else is available for this turn';
  end if;

  insert into public.turn_passes (
    trip_id, turn_id, passed_by_member_id, passed_to_member_id
  ) values (
    v_turn.trip_id, v_turn.id, v_turn.member_id, v_next_member.id
  );

  update public.turns set member_id = v_next_member.id where id = v_turn.id;

  return json_build_object(
    'passed', true,
    'turn_id', v_turn.id,
    'next_member', row_to_json(v_next_member)
  );
end;
$$;

create or replace function public.list_my_trips()
returns table(
  id uuid,
  slug text,
  name text,
  created_by uuid,
  created_at timestamptz,
  member_id uuid,
  display_name text,
  member_count bigint,
  photo_count bigint,
  is_creator boolean,
  preview_photos jsonb
)
language sql
stable security definer
set search_path = public
as $$
  select
    t.id,
    t.slug,
    t.name,
    t.created_by,
    t.created_at,
    me.id as member_id,
    me.display_name,
    (select count(*) from public.members m2 where m2.trip_id = t.id) as member_count,
    (select count(*) from public.photos p where p.trip_id = t.id) as photo_count,
    (t.created_by = auth.uid()) as is_creator,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id,
        'storage_path', q.storage_path,
        'created_at', q.created_at,
        'display_name', q.display_name,
        'is_anchor', q.is_anchor
      ) order by q.created_at desc)
      from (
        select p.id, p.storage_path, p.created_at, m.display_name, p.is_anchor
        from public.photos p
        join public.members m on m.id = p.member_id
        where p.trip_id = t.id
        order by p.created_at desc
        limit 12
      ) q
    ), '[]'::jsonb) as preview_photos
  from public.members me
  join public.trips t on t.id = me.trip_id
  where me.user_id = auth.uid()
  order by t.created_at desc;
$$;

create or replace function public.delete_trip_record(p_trip_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip public.trips;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select * into v_trip
  from public.trips
  where id = p_trip_id and created_by = auth.uid();

  if v_trip.id is null then
    raise exception 'only the trip creator can delete this trip';
  end if;

  delete from public.trips where id = p_trip_id;
  return json_build_object('deleted', true, 'trip_id', p_trip_id, 'slug', v_trip.slug);
end;
$$;

create or replace function public.ensure_daily_turns(p_date date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_member uuid;
  v_count integer := 0;
begin
  for r in
    select t.id
    from public.trips t
    where t.created_at > now() - interval '30 days'
      and exists (select 1 from public.members m where m.trip_id = t.id)
      and not exists (select 1 from public.turns tu where tu.trip_id = t.id and tu.turn_date = p_date)
  loop
    select m.id into v_member
    from public.members m
    where m.trip_id = r.id
    order by (select max(tu.turn_date) from public.turns tu where tu.member_id = m.id) asc nulls first, random()
    limit 1;

    if v_member is not null then
      insert into public.turns (trip_id, member_id, turn_date)
      values (r.id, v_member, p_date)
      on conflict (trip_id, turn_date) do nothing;
      v_count := v_count + 1;
    end if;
  end loop;

  update public.turns set status = 'skipped'
  where status = 'pending' and turn_date < current_date;

  return v_count;
end;
$$;

create or replace function public.touch_main_photo_caption_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.caption := btrim(new.caption);
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists touch_main_photo_caption_updated_at on public.main_photo_captions;
create trigger touch_main_photo_caption_updated_at
before insert or update on public.main_photo_captions
for each row execute function public.touch_main_photo_caption_updated_at();

create or replace function public.clear_main_photo_caption(p_photo_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_trip_id uuid;
begin
  select c.trip_id into v_trip_id
  from public.main_photo_captions c
  where c.photo_id = p_photo_id;

  if v_trip_id is null then return false; end if;
  if not public.is_trip_member(v_trip_id) then
    raise exception 'Not a member of this trip';
  end if;

  delete from public.main_photo_captions where photo_id = p_photo_id;
  return true;
end;
$$;

create or replace function public.get_yourturn_stable_app()
returns text
language sql
stable security definer
set search_path = public
as $$
  select html from public.app_assets
  where asset_key = 'yourturn_wrapper_v9'
  limit 1;
$$;

create or replace function public.decode_internal_asset(p_encoded text, p_key integer default 73)
returns text
language plpgsql
immutable strict
set search_path = public
as $$
declare
  v_bytes bytea := decode(p_encoded, 'base64');
  i integer;
begin
  if length(v_bytes) = 0 then return ''; end if;
  for i in 0..length(v_bytes)-1 loop
    v_bytes := set_byte(v_bytes, i, get_byte(v_bytes, i) # p_key);
  end loop;
  return convert_from(v_bytes, 'UTF8');
end;
$$;

-- RLS policies
create policy "authenticated can create trip" on public.trips
for insert to authenticated
with check (auth.uid() is not null and created_by = auth.uid());

create policy "members can read trip" on public.trips
for select to authenticated
using (public.is_trip_member(id));

create policy "members can read crew" on public.members
for select to authenticated
using (public.is_trip_member(trip_id));

create policy "member can update own name" on public.members
for update to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "members can read photos" on public.photos
for select to authenticated
using (public.is_trip_member(trip_id));

create policy "members can add photos" on public.photos
for insert to authenticated
with check (
  public.is_trip_member(trip_id)
  and member_id in (select id from public.members where user_id = auth.uid())
);

create policy "member can delete own photo" on public.photos
for delete to authenticated
using (member_id in (select id from public.members where user_id = auth.uid()));

create policy "members can read turns" on public.turns
for select to authenticated
using (public.is_trip_member(trip_id));

create policy "turn holder can update" on public.turns
for update to authenticated
using (member_id in (select id from public.members where user_id = auth.uid()));

create policy "members can read likes" on public.likes
for select to authenticated
using (
  exists (
    select 1 from public.photos p
    where p.id = likes.photo_id and public.is_trip_member(p.trip_id)
  )
);

create policy "members can like" on public.likes
for insert to authenticated
with check (
  member_id in (select id from public.members where user_id = auth.uid())
  and exists (
    select 1 from public.photos p
    where p.id = likes.photo_id and public.is_trip_member(p.trip_id)
  )
);

create policy "member can unlike" on public.likes
for delete to authenticated
using (member_id in (select id from public.members where user_id = auth.uid()));

create policy "members can read turn passes" on public.turn_passes
for select to authenticated
using (public.is_trip_member(trip_id));

create policy "member manages own subscriptions" on public.push_subscriptions
for all to authenticated
using (member_id in (select id from public.members where user_id = auth.uid()))
with check (member_id in (select id from public.members where user_id = auth.uid()));

create policy "trip members can read shared caption" on public.main_photo_captions
for select to authenticated
using (public.is_trip_member(trip_id));

create policy "trip members can create shared caption" on public.main_photo_captions
for insert to authenticated
with check (
  public.is_trip_member(trip_id)
  and updated_by_member_id in (
    select m.id from public.members m
    where m.user_id = auth.uid() and m.trip_id = main_photo_captions.trip_id
  )
  and exists (
    select 1 from public.photos p
    where p.id = main_photo_captions.photo_id
      and p.trip_id = main_photo_captions.trip_id
      and p.is_anchor = true
  )
);

create policy "trip members can edit shared caption" on public.main_photo_captions
for update to authenticated
using (public.is_trip_member(trip_id))
with check (
  public.is_trip_member(trip_id)
  and updated_by_member_id in (
    select m.id from public.members m
    where m.user_id = auth.uid() and m.trip_id = main_photo_captions.trip_id
  )
  and exists (
    select 1 from public.photos p
    where p.id = main_photo_captions.photo_id
      and p.trip_id = main_photo_captions.trip_id
      and p.is_anchor = true
  )
);

create policy "trip members can clear shared caption" on public.main_photo_captions
for delete to authenticated
using (public.is_trip_member(trip_id));

-- Function grants
revoke all on function public.peek_trip(text) from public, anon;
revoke all on function public.join_trip(text,text) from public, anon;
revoke all on function public.create_trip(text,text) from public, anon;
revoke all on function public.complete_turn(uuid,uuid) from public, anon;
revoke all on function public.pass_turn(uuid) from public, anon;
revoke all on function public.list_my_trips() from public, anon;
revoke all on function public.delete_trip_record(uuid) from public, anon;
revoke all on function public.clear_main_photo_caption(uuid) from public, anon;
revoke all on function public.ensure_daily_turns(date) from public, anon, authenticated;

grant execute on function public.peek_trip(text) to authenticated;
grant execute on function public.join_trip(text,text) to authenticated;
grant execute on function public.create_trip(text,text) to authenticated;
grant execute on function public.complete_turn(uuid,uuid) to authenticated;
grant execute on function public.pass_turn(uuid) to authenticated;
grant execute on function public.list_my_trips() to authenticated;
grant execute on function public.delete_trip_record(uuid) to authenticated;
grant execute on function public.clear_main_photo_caption(uuid) to authenticated;
grant execute on function public.ensure_daily_turns(date) to service_role;
grant execute on function public.get_yourturn_stable_app() to anon, authenticated, service_role;

-- Private photos bucket
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'photos',
  'photos',
  false,
  26214400,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "trip members can read photos bucket" on storage.objects
for select to authenticated
using (
  bucket_id = 'photos'
  and public.is_trip_member((storage.foldername(name))[1]::uuid)
);

create policy "trip members can upload photos bucket" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'photos'
  and public.is_trip_member((storage.foldername(name))[1]::uuid)
);

create policy "owner can delete own storage objects" on storage.objects
for delete to authenticated
using (bucket_id = 'photos' and owner = auth.uid());
