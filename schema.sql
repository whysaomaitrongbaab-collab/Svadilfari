-- ============================================================
--  STEEL CALC v2 — Schema
--  รันใน Supabase > SQL Editor
-- ============================================================
create extension if not exists "uuid-ossp";

-- profiles (auto-created on signup)
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz default now()
);
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', new.email));
  return new;
end;$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- projects
create table if not exists public.projects (
  id           uuid primary key default uuid_generate_v4(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  name         text not null,
  description  text,
  location     text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);
create index on public.projects(user_id);

-- members (รายการเสา/คาน แต่ละชิ้น)
create table if not exists public.members (
  id           uuid primary key default uuid_generate_v4(),
  project_id   uuid not null references public.projects(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  member_type  text not null default 'column', -- 'column' | 'beam' | 'slab' | 'footing'
  name         text not null,                  -- เช่น C1, B-GL1, S1
  floor        text,                           -- ชั้น เช่น 1F, 2F, RF
  -- รายการเหล็ก (jsonb array)
  rebars       jsonb default '[]',
  -- [{ "mark":"T1", "diameter":16, "length_mm":6000, "quantity":8, "weight_kg":75.74, "note":"" }]
  total_weight_kg numeric(10,2) default 0,
  image_url    text,                           -- รูปแบบที่อัพโหลด
  ai_raw       text,                           -- ผล AI ดิบ
  notes        text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);
create index on public.members(project_id);

-- auto updated_at
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;$$;
create trigger trg_projects_upd before update on public.projects for each row execute function public.set_updated_at();
create trigger trg_members_upd  before update on public.members  for each row execute function public.set_updated_at();

-- RLS
alter table public.profiles enable row level security;
alter table public.projects  enable row level security;
alter table public.members   enable row level security;

create policy "own profile"   on public.profiles for all using (auth.uid()=id);
create policy "own projects"  on public.projects for all using (auth.uid()=user_id);
create policy "own members"   on public.members  for all using (auth.uid()=user_id);

-- Storage bucket สำหรับรูปแบบ
insert into storage.buckets (id, name, public) values ('drawings','drawings',true) on conflict do nothing;
create policy "upload drawings" on storage.objects for insert with check (bucket_id='drawings' and auth.uid() is not null);
create policy "view drawings"   on storage.objects for select using (bucket_id='drawings');
create policy "delete drawings" on storage.objects for delete using (bucket_id='drawings' and auth.uid()::text = (storage.foldername(name))[1]);

select 'Steel Calc v2 schema ready ✓' as result;
