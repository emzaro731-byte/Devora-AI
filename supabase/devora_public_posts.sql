-- Devora AI public community posts / reusable templates
-- Run this once in Supabase Dashboard > SQL Editor.
create table if not exists public.devora_public_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('image','video','music')),
  prompt text not null default '',
  model text not null default '',
  media_url text not null,
  created_at timestamptz not null default now()
);

alter table public.devora_public_posts enable row level security;

drop policy if exists "Anyone can view public Devora posts" on public.devora_public_posts;
create policy "Anyone can view public Devora posts"
on public.devora_public_posts for select
to anon, authenticated
using (true);

drop policy if exists "Users can publish their own Devora posts" on public.devora_public_posts;
create policy "Users can publish their own Devora posts"
on public.devora_public_posts for insert
to authenticated
with check (auth.uid() = user_id);

grant select on public.devora_public_posts to anon, authenticated;
grant insert on public.devora_public_posts to authenticated;
