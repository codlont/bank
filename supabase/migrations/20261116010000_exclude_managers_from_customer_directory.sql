-- Allow authenticated managers to list manager user IDs, while keeping
-- the manager directory invisible to ordinary customer sessions.
create schema if not exists private;

create or replace function private.is_manager()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.manager_users mu
    where mu.user_id = (select auth.uid())
  );
$$;

revoke all on function private.is_manager() from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.is_manager() to authenticated;

drop policy if exists "Managers can read manager directory" on public.manager_users;
create policy "Managers can read manager directory"
on public.manager_users
for select
to authenticated
using ((select private.is_manager()));
