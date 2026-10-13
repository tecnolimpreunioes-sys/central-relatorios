-- =====================================================================
-- Relatórios de acesso livre (sem login) (006)
-- relatorios.publico = true: a página abre para qualquer pessoa na Central,
-- sem senha. Controlado em Administração › Configurações.
-- O Quadro de Vagas passa para a área Operacional, com acesso livre.
-- Requer 001 e 005. Aplicar no HML e na VM.
-- =====================================================================
alter table central.relatorios add column if not exists publico boolean not null default false;

-- acesso a um relatório: livre (publico) ou admin / área liberada / relatório liberado
create or replace function central.pode_ver_relatorio(p_slug text)
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select exists(
    select 1 from central.relatorios r
    join central.areas a on a.id = r.area_id
    where r.slug = p_slug and r.ativo and a.ativo
      and ( r.publico
         or ( central.usuario_ok() and (
                 central.eh_admin()
              or exists(select 1 from central.acessos_area aa where aa.usuario_id = auth.uid() and aa.area_id = r.area_id)
              or exists(select 1 from central.acessos_relatorio ar where ar.usuario_id = auth.uid() and ar.relatorio_id = r.id)))));
$$;

create or replace function central.pode_ver_relatorio_id(p_id uuid)
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select exists(select 1 from central.relatorios r where r.id = p_id and r.ativo and r.publico)
    or (central.usuario_ok() and (central.eh_admin()
    or exists(select 1 from central.relatorios r
              where r.id = p_id and (
                exists(select 1 from central.acessos_area aa where aa.usuario_id = auth.uid() and aa.area_id = r.area_id)
             or exists(select 1 from central.acessos_relatorio ar where ar.usuario_id = auth.uid() and ar.relatorio_id = r.id)))));
$$;

-- contexto da página de um relatório: permissão + área atual (breadcrumb)
create or replace function central.relatorio_contexto(p_slug text)
returns jsonb language sql stable security definer set search_path = central, pg_temp as $$
  select case when central.pode_ver_relatorio(p_slug)
    then (select jsonb_build_object('pode_ver', true, 'publico', r.publico, 'area_slug', a.slug, 'area_nome', a.nome)
          from central.relatorios r join central.areas a on a.id = r.area_id where r.slug = p_slug)
    else jsonb_build_object('pode_ver', false) end;
$$;

-- relatórios livres para a tela inicial de quem não entrou
create or replace function central.relatorios_publicos()
returns table(slug text, nome text, descricao text, categoria text, url text,
              area_slug text, area_nome text, area_icone text, area_cor text)
language sql stable security definer set search_path = central, pg_temp as $$
  select r.slug, r.nome, r.descricao, r.categoria, r.url, a.slug, a.nome, a.icone, a.cor
  from central.relatorios r join central.areas a on a.id = r.area_id
  where r.ativo and r.publico and a.ativo
  order by a.ordem, r.ordem, r.nome;
$$;

grant execute on function central.pode_ver_relatorio(text), central.relatorio_contexto(text),
  central.relatorios_publicos() to anon, authenticated;

-- ---------- Quadro de Vagas: fila também para quem não entrou ----------
alter table central.qv_solicitacoes alter column usuario_id drop not null;

-- logado: até 3 abertas por usuário; sem login: até 10 abertas no total
create or replace function central.qv_antes_inserir()
returns trigger language plpgsql security definer set search_path = central, pg_temp as $$
begin
  if auth.role() = 'service_role' then return new; end if;
  new.usuario_id := auth.uid();
  new.data_emissao := (now() at time zone 'America/Sao_Paulo')::date; -- sempre o dia (competência do mês, como no Senior)
  new.status := 'pendente'; new.mensagem := null; new.resultado := null;
  new.criado_em := now(); new.atualizado_em := now();
  if auth.uid() is null then
    if (select count(*) from central.qv_solicitacoes s
        where s.usuario_id is null and s.status in ('pendente','processando')) >= 10 then
      raise exception 'Muitas gerações em andamento. Tente novamente em alguns instantes.';
    end if;
  elsif (select count(*) from central.qv_solicitacoes s
         where s.usuario_id = auth.uid() and s.status in ('pendente','processando')) >= 3 then
    raise exception 'Aguarde a conclusão das gerações em andamento.';
  end if;
  return new;
end $$;

-- a página grava e acompanha a solicitação por estas funções (com ou sem login)
create or replace function central.qv_solicitar(p_empresas text, p_locais text)
returns uuid language plpgsql volatile security definer set search_path = central, pg_temp as $$
declare v_id uuid;
begin
  if not central.pode_ver_relatorio('quadro-vagas') then
    raise exception 'Sem acesso ao Quadro de Vagas.' using errcode = '42501';
  end if;
  insert into central.qv_solicitacoes(empresas, locais) values (p_empresas, coalesce(p_locais, ''))
  returning id into v_id;
  return v_id;
end $$;

create or replace function central.qv_consultar(p_id uuid)
returns table(status text, mensagem text, resultado jsonb)
language sql stable security definer set search_path = central, pg_temp as $$
  select s.status, s.mensagem, s.resultado from central.qv_solicitacoes s
  where s.id = p_id and central.pode_ver_relatorio('quadro-vagas')
    and (s.usuario_id is null or s.usuario_id = auth.uid());
$$;

revoke all on function central.qv_solicitar(text, text), central.qv_consultar(uuid) from public;
grant execute on function central.qv_solicitar(text, text), central.qv_consultar(uuid) to anon, authenticated;

-- ---------- Quadro de Vagas: área Operacional, acesso livre ----------
update central.relatorios
   set area_id = (select id from central.areas where slug = 'operacional'), publico = true
 where slug = 'quadro-vagas';
