-- The dino leaderboard's database (a Supabase project; run once in its SQL Editor). scripts/leaderboard.gd talks to it.
-- Every run's meat goes in `runs` (anyone can add, no one can change or read the table directly); the boards come
-- from leaderboard(period, me): kilograms added up per player over the day / week / month (Melbourne time:
-- midnight, Monday, the 1st), the top 10 plus your own spot. One run is capped at 5000 kg.
create table public.runs (
  id bigint generated always as identity primary key,
  player uuid not null,
  name text not null check (char_length(name) between 1 and 24),
  kg real not null check (kg >= 0 and kg <= 5000),
  created_at timestamptz not null default now()
);
alter table public.runs enable row level security;
create policy "anyone can add a run" on public.runs for insert to anon with check (true);
grant insert on public.runs to anon;

create or replace function public.leaderboard(period text, me uuid default null)
returns table(rank bigint, name text, kg real, is_me boolean)
language sql security definer set search_path = public stable as $$
  with since as (
    select (date_trunc(case period when 'day' then 'day' when 'week' then 'week' else 'month' end,
      now() at time zone 'Australia/Melbourne') at time zone 'Australia/Melbourne') as t
  ), totals as (
    select player, sum(kg)::real as kg, (array_agg(name order by created_at desc))[1] as name
    from public.runs, since where created_at >= since.t group by player
  ), ranked as (
    select rank() over (order by kg desc) as rank, name, kg, (player = me) as is_me from totals
  )
  select * from ranked where rank <= 10 or is_me order by rank;
$$;
grant execute on function public.leaderboard(text, uuid) to anon;
