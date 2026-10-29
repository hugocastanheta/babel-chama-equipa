-- Babel Chama: publicação sem login. Qualquer pessoa com o endereço pode consultar e alterar a fila.
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.queue_state (
  id integer primary key check (id = 1),
  seq integer not null default 0,
  served integer not null default 0,
  active_id uuid,
  last_reset timestamptz
);
insert into public.queue_state(id,seq,served) values (1,0,0) on conflict (id) do nothing;

create table if not exists public.tickets (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  person text not null,
  dev text not null,
  reason text not null,
  status text not null check(status in ('waiting','called','done')),
  sequence integer not null,
  created_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists tickets_queue_idx on public.tickets(status,dev,sequence);
alter table public.queue_state enable row level security;
alter table public.tickets enable row level security;
drop policy if exists "Public can read queue state" on public.queue_state;
create policy "Public can read queue state" on public.queue_state for select to anon, authenticated using (true);
drop policy if exists "Public can read tickets" on public.tickets;
create policy "Public can read tickets" on public.tickets for select to anon, authenticated using (true);
grant select on public.queue_state, public.tickets to anon, authenticated;

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='tickets') then
    execute 'alter publication supabase_realtime add table public.tickets';
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='queue_state') then
    execute 'alter publication supabase_realtime add table public.queue_state';
  end if;
end $$;

create or replace function public.create_ticket(p_person text,p_dev text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_seq integer; v_dev text; v_ticket public.tickets%rowtype;
begin
  if p_person not in ('Hugo Miguel Castanheta','Filipe Torres','Inês Oliveira','Sónia Cristina Freire Guerreiro','Sara Alexandre','Álvaro Cristino Horta','Edgar Matos','Carlos Falcão','Carlos Miguel Realinho Bragança','Carolina Gameiro Ferreira','Nelson Costa Inácio','Alex Silva','Inês Correia') then raise exception 'Seleciona uma pessoa da equipa.'; end if;
  if length(trim(coalesce(p_reason,'')))=0 or length(p_reason)>500 then raise exception 'Descreve o pedido (máximo 500 caracteres).'; end if;
  perform 1 from public.queue_state where id=1 for update;
  if p_dev='any' then
    select members.name into v_dev from unnest(array['Hugo Miguel Castanheta','Filipe Torres','Inês Oliveira','Sónia Cristina Freire Guerreiro','Sara Alexandre','Álvaro Cristino Horta','Edgar Matos','Carlos Falcão','Carlos Miguel Realinho Bragança','Carolina Gameiro Ferreira','Nelson Costa Inácio','Alex Silva','Inês Correia']) with ordinality as members(name,ord)
    left join (select dev,count(*) n from public.tickets where status in ('waiting','called') group by dev) q on q.dev=members.name
    where members.name<>p_person order by coalesce(q.n,0),members.ord limit 1;
  else v_dev:=p_dev; end if;
  if v_dev is null or v_dev not in ('Hugo Miguel Castanheta','Filipe Torres','Inês Oliveira','Sónia Cristina Freire Guerreiro','Sara Alexandre','Álvaro Cristino Horta','Edgar Matos','Carlos Falcão','Carlos Miguel Realinho Bragança','Carolina Gameiro Ferreira','Nelson Costa Inácio','Alex Silva','Inês Correia') then raise exception 'Escolhe alguém da equipa para atender.'; end if;
  update public.queue_state set seq=seq+1 where id=1 returning seq into v_seq;
  insert into public.tickets(code,person,dev,reason,status,sequence) values ('S-'||lpad(v_seq::text,3,'0'),p_person,v_dev,trim(p_reason),'waiting',v_seq) returning * into v_ticket;
  return jsonb_build_object('id',v_ticket.id,'code',v_ticket.code,'person',v_ticket.person,'dev',v_ticket.dev,'reason',v_ticket.reason,'status',v_ticket.status,'sequence',v_ticket.sequence,'created_at',v_ticket.created_at);
end $$;

create or replace function public.call_next(p_dev text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_ticket public.tickets%rowtype;
begin
  perform 1 from public.queue_state where id=1 for update;
  if (select active_id from public.queue_state where id=1) is not null then raise exception 'Já há um atendimento em curso.'; end if;
  select id into v_id from public.tickets where dev=p_dev and status='waiting' order by sequence,created_at limit 1 for update;
  if v_id is null then raise exception 'Não há pedidos à espera nesta fila.'; end if;
  update public.tickets set status='called' where id=v_id returning * into v_ticket;
  update public.queue_state set active_id=v_id where id=1;
  return jsonb_build_object('id',v_ticket.id,'code',v_ticket.code,'person',v_ticket.person,'dev',v_ticket.dev,'reason',v_ticket.reason,'status',v_ticket.status,'sequence',v_ticket.sequence,'created_at',v_ticket.created_at);
end $$;

create or replace function public.finish_active()
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid;
begin
  perform 1 from public.queue_state where id=1 for update;
  select active_id into v_id from public.queue_state where id=1;
  if v_id is null then raise exception 'Não há atendimento ativo.'; end if;
  update public.tickets set status='done',finished_at=now() where id=v_id;
  update public.queue_state set active_id=null,served=served+1 where id=1;
  return true;
end $$;

create or replace function public.clear_queue()
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
  perform 1 from public.queue_state where id=1 for update;
  delete from public.tickets where status in ('waiting','called');
  update public.queue_state set active_id=null where id=1;
  return true;
end $$;

create or replace function public.reset_queue_if_lisbon_20()
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if extract(hour from (now() at time zone 'Europe/Lisbon'))<>20 then return false; end if;
  perform 1 from public.queue_state where id=1 for update;
  delete from public.tickets;
  update public.queue_state set active_id=null,seq=0,served=0,last_reset=now() where id=1;
  return true;
end $$;

grant execute on function public.create_ticket(text,text,text) to anon,authenticated;
grant execute on function public.call_next(text) to anon,authenticated;
grant execute on function public.finish_active() to anon,authenticated;
grant execute on function public.clear_queue() to anon,authenticated;
grant execute on function public.reset_queue_if_lisbon_20() to anon,authenticated;

select cron.schedule('babel-chama-reset-lisbon-19utc','0 19 * * *','select public.reset_queue_if_lisbon_20()');
select cron.schedule('babel-chama-reset-lisbon-20utc','0 20 * * *','select public.reset_queue_if_lisbon_20()');
