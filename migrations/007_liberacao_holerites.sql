-- =====================================================================
-- Liberação de holerites RH 24h (007)
-- Painel da T.I. (slug liberacao-holerites): espelho das folhas (R044CAL) e
-- das liberações (USU_TLIBHOL do Sapiens), fila de pedidos e histórico.
-- Fluxo: o painel chama lh_solicitar → o worker da TECNOLIMP12 (service_role)
-- pega o pedido (lh_proximo), grava na USU_TLIBHOL, informa o que aplicou
-- (lh_concluir) e relê o Sapiens (lh_espelhar). O Oracle só é tocado quando
-- chega pedido; a fila em si é barata (mesmo padrão do Quadro de Vagas).
-- Alteração feita direto no Oracle (SQL de contingência) aparece no
-- histórico como "fora do painel" na próxima leitura.
-- Requer 001, 004 e 006. Aplicar no HML e na VM.
-- =====================================================================

-- ---------- tabelas ----------
-- espelho da R044CAL: folha mensal (TipCal 11) mais recente por empresa + competência
create table if not exists central.lh_folhas (
  num_emp  smallint not null check (num_emp between 1 and 9999),
  per_ref  date not null check (extract(day from per_ref) = 1),
  cod_cal  integer not null,
  dat_pag  date not null,
  lido_em  timestamptz not null default now(),
  primary key (num_emp, per_ref)
);

-- espelho da USU_TLIBHOL (sem linha = bloqueado, como no Sapiens)
create table if not exists central.lh_liberacoes (
  num_emp  smallint not null check (num_emp between 1 and 9999),
  per_ref  date not null check (extract(day from per_ref) = 1),
  dat_ini  date not null,
  sit_lib  smallint not null check (sit_lib in (0, 1)),
  usu_lib  text not null default '' check (length(usu_lib) <= 30),
  dat_gra  date,
  obs_lib  text not null default '' check (length(obs_lib) <= 60),
  lido_em  timestamptz not null default now(),
  primary key (num_emp, per_ref)
);

-- fila de cliques do painel
create table if not exists central.lh_pedidos (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid references central.perfis(id) on delete set null,
  usuario_login text not null check (length(usuario_login) between 2 and 30),
  acao          text not null check (acao in ('liberar','agendar','agendar_padrao','bloquear','atualizar')),
  data_ini      date,                                   -- liberar = hoje; agendar = data; padrão/bloquear/atualizar = null
  obs           text not null default '' check (length(obs) <= 60),
  alvos         jsonb not null default '[]'::jsonb,     -- [{"emp":3,"per":"2026-09-01"}, ...]
  status        text not null default 'pendente' check (status in ('pendente','processando','aplicado','erro')),
  mensagem      text,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists lh_pedidos_fila_idx on central.lh_pedidos (criado_em) where status = 'pendente';
create index if not exists lh_pedidos_criado_idx on central.lh_pedidos (criado_em desc);

-- histórico (auditoria permanente)
create table if not exists central.lh_log (
  id        bigint generated always as identity primary key,
  em        timestamptz not null default now(),
  usuario   text not null,
  num_emp   smallint not null,
  per_ref   date not null,
  acao      text not null check (acao in ('Liberado','Agendado','Bloqueado')),
  de        text not null,
  para      text not null,
  origem    text not null check (origem in ('painel','fora_do_painel')),
  obs       text not null default '',
  pedido_id uuid references central.lh_pedidos(id) on delete set null
);
create index if not exists lh_log_em_idx on central.lh_log (em desc);
create index if not exists lh_log_alvo_idx on central.lh_log (num_emp, per_ref, em desc);

-- ---------- regras ----------
create or replace function central.lh_hoje()
returns date language sql stable set search_path = central, pg_temp as $$
  select (now() at time zone 'America/Sao_Paulo')::date;
$$;

-- painel só com login (nunca acesso livre) e permissão no slug
create or replace function central.lh_pode()
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select auth.uid() is not null and central.usuario_ok() and central.pode_ver_relatorio('liberacao-holerites');
$$;

-- texto da situação, igual ao painel: "Bloqueado" / "a partir de dd/mm/aaaa" / "desde dd/mm/aaaa"
create or replace function central.lh_descreve(p_sit smallint, p_ini date)
returns text language sql stable set search_path = central, pg_temp as $$
  select case when p_sit is null then 'Bloqueado (sem registro)'
              when p_sit = 0 then 'Bloqueado'
              when p_ini > central.lh_hoje() then 'a partir de ' || to_char(p_ini, 'DD/MM/YYYY')
              else 'desde ' || to_char(p_ini, 'DD/MM/YYYY') end;
$$;

-- grava uma linha no espelho e registra no histórico se a situação mudou
create or replace function central.lh_gravar_espelho(
  p_emp smallint, p_per date, p_sit smallint, p_ini date, p_usu text, p_gra date, p_obs text,
  p_origem text, p_pedido uuid)
returns boolean language plpgsql security definer set search_path = central, pg_temp as $$
declare o_sit smallint; o_ini date; mudou boolean;
begin
  select sit_lib, dat_ini into o_sit, o_ini from central.lh_liberacoes where num_emp = p_emp and per_ref = p_per;
  mudou := o_sit is distinct from p_sit or o_ini is distinct from p_ini;
  if p_sit is null then
    delete from central.lh_liberacoes where num_emp = p_emp and per_ref = p_per;
  else
    insert into central.lh_liberacoes(num_emp, per_ref, dat_ini, sit_lib, usu_lib, dat_gra, obs_lib, lido_em)
    values (p_emp, p_per, p_ini, p_sit, left(coalesce(p_usu, ''), 30), p_gra, left(coalesce(p_obs, ''), 60), now())
    on conflict (num_emp, per_ref) do update
      set dat_ini = excluded.dat_ini, sit_lib = excluded.sit_lib, usu_lib = excluded.usu_lib,
          dat_gra = excluded.dat_gra, obs_lib = excluded.obs_lib, lido_em = excluded.lido_em;
  end if;
  if mudou then
    insert into central.lh_log(usuario, num_emp, per_ref, acao, de, para, origem, obs, pedido_id)
    values (coalesce(nullif(p_usu, ''), 'desconhecido'), p_emp, p_per,
            case when coalesce(p_sit, 0) = 0 then 'Bloqueado' when p_ini > central.lh_hoje() then 'Agendado' else 'Liberado' end,
            central.lh_descreve(o_sit, o_ini), central.lh_descreve(p_sit, p_ini), p_origem, coalesce(p_obs, ''), p_pedido);
  end if;
  return mudou;
end $$;

-- ---------- painel ----------
-- registra um clique. Valida tudo aqui: o navegador não escreve direto em nenhuma tabela.
create or replace function central.lh_solicitar(p_acao text, p_alvos jsonb default '[]'::jsonb,
                                                p_data_ini date default null, p_obs text default '')
returns uuid language plpgsql volatile security definer set search_path = central, pg_temp as $$
declare v_id uuid; v_login text; v_obs text := btrim(coalesce(p_obs, '')); v_ini date; v_alvos jsonb := '[]'::jsonb;
        v_hoje date := central.lh_hoje(); a jsonb; v_emp int; v_per date;
begin
  if not central.lh_pode() then
    raise exception 'Sem acesso à liberação de holerites.' using errcode = '42501';
  end if;
  if p_acao is null or p_acao not in ('liberar','agendar','agendar_padrao','bloquear','atualizar') then
    raise exception 'Ação inválida.';
  end if;
  if length(v_obs) > 60 then raise exception 'Observação com mais de 60 caracteres.'; end if;
  if p_acao = 'bloquear' and v_obs = '' then raise exception 'Informe o motivo do bloqueio.'; end if;

  if p_acao <> 'atualizar' then
    if jsonb_typeof(p_alvos) is distinct from 'array' or jsonb_array_length(p_alvos) not between 1 and 20 then
      raise exception 'Informe de 1 a 20 empresas/competências.';
    end if;
    for a in select * from jsonb_array_elements(p_alvos) loop
      begin
        v_emp := (a->>'emp')::int; v_per := (a->>'per')::date;
      exception when others then raise exception 'Empresa/competência inválida.';
      end;
      if v_emp is null or v_per is null then raise exception 'Empresa/competência inválida.'; end if;
      if not exists(select 1 from central.lh_folhas f where f.num_emp = v_emp and f.per_ref = v_per) then
        raise exception 'Empresa % sem folha calculada em %.', v_emp, to_char(v_per, 'MM/YYYY');
      end if;
      if v_alvos @> jsonb_build_array(jsonb_build_object('emp', v_emp, 'per', v_per)) then continue; end if;
      v_alvos := v_alvos || jsonb_build_array(jsonb_build_object('emp', v_emp, 'per', v_per));
    end loop;
  end if;

  v_ini := case p_acao when 'liberar' then v_hoje when 'agendar' then p_data_ini end;
  if p_acao = 'agendar' and (p_data_ini is null or p_data_ini <= v_hoje) then
    raise exception 'A data do agendamento precisa ser depois de hoje.';
  end if;

  if (select count(*) from central.lh_pedidos where status in ('pendente','processando')) >= 20 then
    raise exception 'Muitos pedidos aguardando o integrador. Aguarde ou use o SQL de contingência.';
  end if;

  select p.login into v_login from central.perfis p where p.id = auth.uid();
  insert into central.lh_pedidos(usuario_id, usuario_login, acao, data_ini, obs, alvos)
  values (auth.uid(), left(v_login, 30), p_acao, v_ini, v_obs, v_alvos)
  returning id into v_id;
  return v_id;
end $$;

-- ---------- worker (service_role) ----------
-- pega o próximo pedido (um por vez, sem disputa entre instâncias)
create or replace function central.lh_proximo()
returns setof central.lh_pedidos language sql volatile security definer set search_path = central, pg_temp as $$
  update central.lh_pedidos p set status = 'processando', atualizado_em = now()
  where p.id = (select id from central.lh_pedidos
                where status = 'pendente' order by criado_em limit 1 for update skip locked)
  returning p.*;
$$;

-- encerra o pedido. p_aplicados = linhas como ficaram na USU_TLIBHOL:
-- [{"emp":3,"per":"2026-09-01","sit":1,"ini":"2026-10-04","gra":"2026-10-14"}]
create or replace function central.lh_concluir(p_id uuid, p_status text, p_mensagem text default null,
                                               p_aplicados jsonb default '[]'::jsonb)
returns void language plpgsql volatile security definer set search_path = central, pg_temp as $$
declare p central.lh_pedidos; a jsonb;
begin
  if p_status not in ('aplicado','erro') then raise exception 'Status inválido.'; end if;
  select * into p from central.lh_pedidos where id = p_id for update;
  if not found then raise exception 'Pedido não encontrado.'; end if;
  for a in select * from jsonb_array_elements(coalesce(p_aplicados, '[]'::jsonb)) loop
    perform central.lh_gravar_espelho((a->>'emp')::smallint, (a->>'per')::date, (a->>'sit')::smallint,
      (a->>'ini')::date, p.usuario_login, (a->>'gra')::date, p.obs, 'painel', p.id);
  end loop;
  update central.lh_pedidos set status = p_status, mensagem = p_mensagem, atualizado_em = now() where id = p_id;
end $$;

-- relê o Sapiens: substitui o espelho a partir de p_desde (início da janela do portal).
-- O que mudou sem passar pelo painel entra no histórico como "fora do painel".
-- p_folhas:     [{"emp":3,"per":"2026-09-01","codcal":512,"datpag":"2026-10-06"}]
-- p_liberacoes: [{"emp":3,"per":"2026-09-01","sit":1,"ini":"2026-10-05","usu":"ygor.adm","gra":"2026-10-13","obs":"..."}]
create or replace function central.lh_espelhar(p_desde date, p_folhas jsonb, p_liberacoes jsonb)
returns integer language plpgsql volatile security definer set search_path = central, pg_temp as $$
declare a jsonb; r record; n int := 0;
begin
  delete from central.lh_folhas;
  insert into central.lh_folhas(num_emp, per_ref, cod_cal, dat_pag, lido_em)
  select (f->>'emp')::smallint, (f->>'per')::date, (f->>'codcal')::int, (f->>'datpag')::date, now()
  from jsonb_array_elements(coalesce(p_folhas, '[]'::jsonb)) f;

  delete from central.lh_liberacoes where per_ref < p_desde;          -- saiu da janela (o histórico fica)
  for a in select * from jsonb_array_elements(coalesce(p_liberacoes, '[]'::jsonb)) loop
    if (a->>'per')::date < p_desde then continue; end if;
    if central.lh_gravar_espelho((a->>'emp')::smallint, (a->>'per')::date, (a->>'sit')::smallint, (a->>'ini')::date,
         a->>'usu', (a->>'gra')::date, a->>'obs', 'fora_do_painel', null) then n := n + 1; end if;
  end loop;
  -- linha apagada direto no Oracle = volta a ficar bloqueado
  for r in select l.num_emp, l.per_ref from central.lh_liberacoes l
           where not exists(select 1 from jsonb_array_elements(coalesce(p_liberacoes, '[]'::jsonb)) x
                            where (x->>'emp')::smallint = l.num_emp and (x->>'per')::date = l.per_ref) loop
    perform central.lh_gravar_espelho(r.num_emp, r.per_ref, null, null, 'fora do painel', null, '', 'fora_do_painel', null);
    n := n + 1;
  end loop;
  return n;
end $$;

-- processando há mais de 10 min = travou; pendente há mais de 1 dia = expirou; fila com mais de 90 dias sai
create or replace function central.lh_manutencao()
returns void language sql volatile security definer set search_path = central, pg_temp as $$
  update central.lh_pedidos set status = 'erro', mensagem = 'Tempo esgotado no integrador.', atualizado_em = now()
  where status = 'processando' and atualizado_em < now() - interval '10 minutes';
  update central.lh_pedidos set status = 'erro', mensagem = 'Expirado: o integrador ficou fora do ar. Refaça o pedido.', atualizado_em = now()
  where status = 'pendente' and criado_em < now() - interval '1 day';
  delete from central.lh_pedidos where criado_em < now() - interval '90 days' and status in ('aplicado','erro');
$$;

-- ---------- privilégios ----------
revoke all on central.lh_folhas, central.lh_liberacoes, central.lh_pedidos, central.lh_log from anon, authenticated;
grant select on central.lh_folhas, central.lh_liberacoes, central.lh_pedidos, central.lh_log to authenticated;
grant all on central.lh_folhas, central.lh_liberacoes, central.lh_pedidos, central.lh_log to service_role;
grant usage on all sequences in schema central to service_role;

revoke all on function central.lh_hoje(), central.lh_pode(), central.lh_descreve(smallint, date),
  central.lh_gravar_espelho(smallint, date, smallint, date, text, date, text, text, uuid),
  central.lh_solicitar(text, jsonb, date, text), central.lh_proximo(),
  central.lh_concluir(uuid, text, text, jsonb), central.lh_espelhar(date, jsonb, jsonb),
  central.lh_manutencao() from public, anon, authenticated;
-- lh_pode é chamada pelas policies de leitura: precisa de execute para quem lê
grant execute on function central.lh_solicitar(text, jsonb, date, text), central.lh_pode(), central.lh_hoje() to authenticated;
grant execute on function central.lh_hoje(), central.lh_pode(), central.lh_descreve(smallint, date),
  central.lh_gravar_espelho(smallint, date, smallint, date, text, date, text, text, uuid),
  central.lh_solicitar(text, jsonb, date, text), central.lh_proximo(),
  central.lh_concluir(uuid, text, text, jsonb), central.lh_espelhar(date, jsonb, jsonb),
  central.lh_manutencao() to service_role;

-- ---------- RLS: leitura só para quem tem o painel; escrita só pelas funções ----------
alter table central.lh_folhas     enable row level security;
alter table central.lh_liberacoes enable row level security;
alter table central.lh_pedidos    enable row level security;
alter table central.lh_log        enable row level security;
drop policy if exists lh_folhas_le on central.lh_folhas;
drop policy if exists lh_liberacoes_le on central.lh_liberacoes;
drop policy if exists lh_pedidos_le on central.lh_pedidos;
drop policy if exists lh_log_le on central.lh_log;
create policy lh_folhas_le     on central.lh_folhas     for select to authenticated using (central.lh_pode());
create policy lh_liberacoes_le on central.lh_liberacoes for select to authenticated using (central.lh_pode());
create policy lh_pedidos_le    on central.lh_pedidos    for select to authenticated using (central.lh_pode());
create policy lh_log_le        on central.lh_log        for select to authenticated using (central.lh_pode());

-- ---------- cadastro na Central (área T.I., nunca acesso livre) ----------
insert into central.relatorios(area_id, slug, nome, descricao, categoria, url, ordem)
select id, 'liberacao-holerites', 'Liberação de Holerites (RH 24h)',
       'Libera, agenda e bloqueia o holerite do portal RH 24h por empresa e competência.',
       'RH 24h', 'relatorios/liberacao-holerites/', 20
from central.areas where slug = 'ti'
on conflict (slug) do nothing;

do $$
begin
  if not exists(select 1 from pg_constraint where conname = 'relatorios_lh_nao_publico') then
    alter table central.relatorios add constraint relatorios_lh_nao_publico
      check (not (slug = 'liberacao-holerites' and publico));
  end if;
end $$;
