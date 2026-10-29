-- Health dashboard schema (applied to Supabase project cowljafosekwvxithwjd).
-- Health data itself is NOT stored in this repository; it lives only in these tables.
-- Every table is readable solely by users listed in public.health_viewers.

create table public.health_viewers (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create or replace function public.is_health_viewer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.health_viewers v where v.user_id = auth.uid());
$$;
revoke execute on function public.is_health_viewer() from public, anon;
grant execute on function public.is_health_viewer() to authenticated;

create table public.health_checkups (
  year int primary key,
  exam_date date not null,
  age int not null,
  institution text not null,
  summary text not null,
  drive_url text,
  storage_path text
);

create table public.health_metrics (
  metric_key text not null,
  year int not null,
  value numeric,
  value_text text,
  flagged boolean not null default false,
  primary key (metric_key, year)
);

create table public.health_metric_defs (
  metric_key text primary key,
  category text not null,
  label text not null,
  unit text,
  ref_text text,
  sort int not null,
  chart jsonb            -- null = table only; otherwise chart config (ref line, axis, takeaway)
);

create table public.health_scorecard (
  system text primary key,
  sort int not null,
  statuses text[] not null check (array_length(statuses, 1) = 6),
  comment text not null
);

create table public.health_followups (
  no int primary key,
  tier int not null check (tier between 1 and 3),
  short_label text not null,
  title text not null,
  data text not null,
  owner text not null,
  action text not null,
  why text,
  timing text not null,
  urgency int not null,
  impact int not null
);

create table public.health_report_sections (
  id text primary key,
  sort int not null,
  nav_label text,
  html text not null
);

do $$
declare t text;
begin
  foreach t in array array['health_viewers','health_checkups','health_metrics','health_metric_defs',
                           'health_scorecard','health_followups','health_report_sections']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
  end loop;
end $$;

create policy "viewer reads own row" on public.health_viewers
  for select to authenticated using (user_id = (select auth.uid()));

create policy "viewers read" on public.health_checkups        for select to authenticated using ((select public.is_health_viewer()));
create policy "viewers read" on public.health_metrics         for select to authenticated using ((select public.is_health_viewer()));
create policy "viewers read" on public.health_metric_defs     for select to authenticated using ((select public.is_health_viewer()));
create policy "viewers read" on public.health_scorecard       for select to authenticated using ((select public.is_health_viewer()));
create policy "viewers read" on public.health_followups       for select to authenticated using ((select public.is_health_viewer()));
create policy "viewers read" on public.health_report_sections for select to authenticated using ((select public.is_health_viewer()));

-- Private bucket for the original PDF reports
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('health-reports', 'health-reports', false, 20971520, array['application/pdf']);

create policy "health viewers read reports" on storage.objects
  for select to authenticated using (bucket_id = 'health-reports' and (select public.is_health_viewer()));
create policy "health viewers upload reports" on storage.objects
  for insert to authenticated with check (bucket_id = 'health-reports' and (select public.is_health_viewer()));
create policy "health viewers replace reports" on storage.objects
  for update to authenticated using (bucket_id = 'health-reports' and (select public.is_health_viewer()));
