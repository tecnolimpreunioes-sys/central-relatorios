-- =====================================================================
-- Papéis por relatório (009)
-- Acesso (entrar no relatório) continua igual: área inteira ou relatório
-- marcado. Papel (o que a pessoa vê ou faz dentro dele) é dado pelo admin,
-- por usuário e por relatório; sem papel ela entra mas não vê dados.
-- Admin tem todos os papéis. Relatório com papéis nunca é de acesso livre.
-- Cada relatório que usa papéis cadastra o catálogo na própria migration
-- (insert em central.relatorio_papeis) e usa central.tem_papel('<slug>','<papel>')
-- nas policies. Requer 001, 004 e 006. Aplicar no HML e na VM.
-- =====================================================================

-- ---------- tabelas ----------
-- catálogo: quais papéis cada relatório oferece (vem da migration do relatório)
create table if not exists central.relatorio_papeis (
  relatorio_id uuid not null references central.relatorios(id) on delete cascade,
  papel        text not null check (papel ~ '^[a-z0-9-]{2,30}$'),
  nome         text not null check (length(btrim(nome)) between 2 and 40),
  descricao    text not null default '' check (length(descricao) <= 200),
  ordem        integer not null default 100,
  primary key (relatorio_id, papel)
);

-- quem tem qual papel (mais de um por pessoa é permitido)
create table if not exists central.acessos_papel (
  usuario_id   uuid not null references central.perfis(id) on delete cascade,
  relatorio_id uuid not null,
  papel        text not null,
  primary key (usuario_id, relatorio_id, papel),
  foreign key (relatorio_id, papel) references central.relatorio_papeis(relatorio_id, papel) on delete cascade
);
create index if not exists acessos_papel_rel_idx on central.acessos_papel(relatorio_id);

-- histórico de concessões/remoções (preenchido só pelo gatilho)
create table if not exists central.acessos_papel_log (
  id             bigint generated always as identity primary key,
  em             timestamptz not null default now(),
  por            uuid,          -- quem mudou (null = migration/service_role)
  por_login      text,
  usuario_id     uuid not null, -- sem FK: o histórico sobrevive à exclusão do usuário
  usuario_login  text,
  relatorio_id   uuid not null,
  relatorio_slug text,
  papel          text not null,
  acao           text not null check (acao in ('concedido','removido'))
);
create index if not exists acessos_papel_log_em_idx on central.acessos_papel_log (em desc);

-- ---------- funções ----------
-- papel no relatório: login ok + acesso (área ou relatório; "acesso livre" não conta) + papel; admin tem todos
create or replace function central.tem_papel(p_slug text, p_papel text)
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select auth.uid() is not null and central.usuario_ok() and exists(
    select 1 from central.relatorios r
    join central.areas a on a.id = r.area_id
    join central.relatorio_papeis rp on rp.relatorio_id = r.id and rp.papel = p_papel
    where r.slug = p_slug and r.ativo and a.ativo
      and ( central.eh_admin()
         or ( ( exists(select 1 from central.acessos_area aa where aa.usuario_id = auth.uid() and aa.area_id = r.area_id)
             or exists(select 1 from central.acessos_relatorio ar where ar.usuario_id = auth.uid() and ar.relatorio_id = r.id))
           and exists(select 1 from central.acessos_papel ap
                      where ap.usuario_id = auth.uid() and ap.relatorio_id = r.id and ap.papel = p_papel))));
$$;

create or replace function central.meus_papeis(p_slug text)
returns text[] language sql stable security definer set search_path = central, pg_temp as $$
  select coalesce(array_agg(rp.papel order by rp.ordem, rp.papel), '{}')
  from central.relatorios r join central.relatorio_papeis rp on rp.relatorio_id = r.id
  where r.slug = p_slug and central.tem_papel(p_slug, rp.papel);
$$;

-- contexto da página (006) + papéis: usa_papeis = o relatório tem catálogo; papeis = os da pessoa
create or replace function central.relatorio_contexto(p_slug text)
returns jsonb language sql stable security definer set search_path = central, pg_temp as $$
  select case when central.pode_ver_relatorio(p_slug)
    then (select jsonb_build_object('pode_ver', true, 'publico', r.publico, 'area_slug', a.slug, 'area_nome', a.nome,
                                    'usa_papeis', exists(select 1 from central.relatorio_papeis rp where rp.relatorio_id = r.id),
                                    'papeis', to_jsonb(central.meus_papeis(p_slug)))
          from central.relatorios r join central.areas a on a.id = r.area_id where r.slug = p_slug)
    else jsonb_build_object('pode_ver', false) end;
$$;

-- admin grava o conjunto de papéis do usuário de uma vez (só a diferença entra no histórico)
-- p_papeis = [{"relatorio_id": "<uuid>", "papel": "rh"}, ...]
create or replace function central.salvar_papeis(p_usuario uuid, p_papeis jsonb)
returns void language plpgsql volatile security definer set search_path = central, pg_temp as $$
begin
  if not central.eh_admin() then
    raise exception 'Só o administrador altera papéis.';
  end if;
  p_papeis := coalesce(p_papeis, '[]'::jsonb);
  if jsonb_typeof(p_papeis) <> 'array' then
    raise exception 'Lista de papéis inválida.';
  end if;
  delete from central.acessos_papel ap
   where ap.usuario_id = p_usuario
     and not exists(select 1 from jsonb_array_elements(p_papeis) x
                    where (x->>'relatorio_id')::uuid = ap.relatorio_id and x->>'papel' = ap.papel);
  insert into central.acessos_papel(usuario_id, relatorio_id, papel)
  select p_usuario, (x->>'relatorio_id')::uuid, x->>'papel' from jsonb_array_elements(p_papeis) x
  on conflict do nothing;
end $$;

-- ---------- gatilhos ----------
create or replace function central.acessos_papel_registrar()
returns trigger language plpgsql security definer set search_path = central, pg_temp as $$
declare v central.acessos_papel%rowtype;
begin
  if tg_op = 'DELETE' then v := old; else v := new; end if;
  insert into central.acessos_papel_log(por, por_login, usuario_id, usuario_login, relatorio_id, relatorio_slug, papel, acao)
  values (auth.uid(), (select login from central.perfis where id = auth.uid()),
          v.usuario_id, (select login from central.perfis where id = v.usuario_id),
          v.relatorio_id, (select slug from central.relatorios where id = v.relatorio_id),
          v.papel, case when tg_op = 'INSERT' then 'concedido' else 'removido' end);
  return null;
end $$;
create or replace trigger acessos_papel_log_tg after insert or delete on central.acessos_papel
  for each row execute function central.acessos_papel_registrar();

-- relatório com papéis sempre pede login (os dois lados: marcar "livre" ou cadastrar papel em relatório livre)
create or replace function central.papeis_exige_login()
returns trigger language plpgsql set search_path = central, pg_temp as $$
begin
  if tg_table_name = 'relatorios' then
    if new.publico and exists(select 1 from central.relatorio_papeis where relatorio_id = new.id) then
      raise exception 'Relatório com papéis sempre pede senha: o que cada pessoa vê depende do papel dela.';
    end if;
  elsif exists(select 1 from central.relatorios where id = new.relatorio_id and publico) then
    raise exception 'Relatório de acesso livre não pode ter papéis. Desligue o acesso livre antes.';
  end if;
  return new;
end $$;
create or replace trigger relatorios_papeis_exige_login before insert or update on central.relatorios
  for each row execute function central.papeis_exige_login();
create or replace trigger relatorio_papeis_exige_login before insert or update on central.relatorio_papeis
  for each row execute function central.papeis_exige_login();

-- ---------- privilégios ----------
revoke all on central.relatorio_papeis, central.acessos_papel, central.acessos_papel_log from anon, authenticated;
grant select on central.relatorio_papeis, central.acessos_papel, central.acessos_papel_log to authenticated;
grant insert, update, delete on central.relatorio_papeis, central.acessos_papel to authenticated;
grant all on central.relatorio_papeis, central.acessos_papel, central.acessos_papel_log to service_role;
grant usage on all sequences in schema central to service_role;

revoke all on function central.tem_papel(text, text), central.meus_papeis(text), central.salvar_papeis(uuid, jsonb),
  central.acessos_papel_registrar(), central.papeis_exige_login() from public, anon, authenticated;
grant execute on function central.tem_papel(text, text), central.meus_papeis(text), central.salvar_papeis(uuid, jsonb)
  to authenticated;
grant execute on function central.tem_papel(text, text), central.meus_papeis(text), central.salvar_papeis(uuid, jsonb),
  central.relatorio_contexto(text) to service_role;
grant execute on function central.relatorio_contexto(text) to anon, authenticated;

-- ---------- RLS ----------
alter table central.relatorio_papeis  enable row level security;
alter table central.acessos_papel     enable row level security;
alter table central.acessos_papel_log enable row level security;
drop policy if exists relatorio_papeis_le on central.relatorio_papeis;
drop policy if exists relatorio_papeis_admin on central.relatorio_papeis;
drop policy if exists acessos_papel_le on central.acessos_papel;
drop policy if exists acessos_papel_admin on central.acessos_papel;
drop policy if exists acessos_papel_log_le on central.acessos_papel_log;
create policy relatorio_papeis_le on central.relatorio_papeis for select to authenticated using (central.usuario_ok());
create policy relatorio_papeis_admin on central.relatorio_papeis for all to authenticated
  using (central.eh_admin()) with check (central.eh_admin());
create policy acessos_papel_le on central.acessos_papel for select to authenticated
  using (usuario_id = auth.uid() or central.eh_admin());
create policy acessos_papel_admin on central.acessos_papel for all to authenticated
  using (central.eh_admin()) with check (central.eh_admin());
create policy acessos_papel_log_le on central.acessos_papel_log for select to authenticated using (central.eh_admin());
