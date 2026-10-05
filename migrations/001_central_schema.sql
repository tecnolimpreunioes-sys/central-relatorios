-- =====================================================================
-- Central de Relatórios Gerenciais — schema "central" (001)
-- Aplicar uma única vez em banco novo (HML Cloud). Na VM, o schema vem
-- pelo migrar-app-cloud-para-vm.sh central.
-- Áreas, relatórios, perfis de usuário e permissões (área inteira ou
-- relatório específico). Toda tabela com RLS. Escrita só por admin.
-- =====================================================================
create schema if not exists central;
grant usage on schema central to anon, authenticated, service_role;

-- ---------- tabelas ----------
create table if not exists central.areas (
  id         uuid primary key default gen_random_uuid(),
  slug       text not null unique check (slug ~ '^[a-z0-9-]{2,40}$'),
  nome       text not null check (length(btrim(nome)) between 2 and 60),
  descricao  text not null default '' check (length(descricao) <= 200),
  icone      text not null default 'pasta',
  cor        text not null default '#004773' check (cor ~ '^#[0-9a-fA-F]{6}$'),
  ordem      integer not null default 100,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

create table if not exists central.relatorios (
  id            uuid primary key default gen_random_uuid(),
  area_id       uuid not null references central.areas(id) on delete restrict,
  slug          text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  nome          text not null check (length(btrim(nome)) between 2 and 90),
  descricao     text not null default '' check (length(descricao) <= 240),
  categoria     text not null default 'Geral' check (length(btrim(categoria)) between 1 and 40),
  url           text not null check (url ~ '^(relatorios/[a-z0-9/_-]+/?|https?://[^\s]+)$'),
  ordem         integer not null default 100,
  ativo         boolean not null default true,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists relatorios_area_idx on central.relatorios(area_id);

create table if not exists central.perfis (
  id                   uuid primary key references auth.users(id) on delete cascade,
  email                text not null,
  nome                 text not null default '',
  is_admin             boolean not null default false,
  must_change_password boolean not null default true,
  ativo                boolean not null default true,
  criado_em            timestamptz not null default now(),
  ultimo_acesso_em     timestamptz
);

create table if not exists central.acessos_area (
  usuario_id uuid not null references central.perfis(id) on delete cascade,
  area_id    uuid not null references central.areas(id) on delete cascade,
  primary key (usuario_id, area_id)
);
create table if not exists central.acessos_relatorio (
  usuario_id   uuid not null references central.perfis(id) on delete cascade,
  relatorio_id uuid not null references central.relatorios(id) on delete cascade,
  primary key (usuario_id, relatorio_id)
);
create index if not exists acessos_relatorio_rel_idx on central.acessos_relatorio(relatorio_id);
create index if not exists acessos_area_area_idx on central.acessos_area(area_id);

-- configurações gerais (senha padrão). Só admin lê/escreve; Edge Function lê com service_role.
create table if not exists central.configuracoes (
  chave text primary key,
  valor text not null
);
insert into central.configuracoes(chave, valor) values ('senha_padrao', 'Tecnolimp@2026')
on conflict (chave) do nothing;

-- ---------- funções de permissão ----------
create or replace function central.usuario_ok()
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select exists(select 1 from central.perfis p
                where p.id = auth.uid() and p.ativo and not p.must_change_password);
$$;

create or replace function central.eh_admin()
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select exists(select 1 from central.perfis p
                where p.id = auth.uid() and p.ativo and p.is_admin and not p.must_change_password);
$$;

-- acesso a um relatório por slug: admin, área inteira liberada ou relatório liberado
create or replace function central.pode_ver_relatorio(p_slug text)
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select central.usuario_ok() and exists(
    select 1 from central.relatorios r
    join central.areas a on a.id = r.area_id
    where r.slug = p_slug and r.ativo and a.ativo
      and ( central.eh_admin()
         or exists(select 1 from central.acessos_area aa where aa.usuario_id = auth.uid() and aa.area_id = r.area_id)
         or exists(select 1 from central.acessos_relatorio ar where ar.usuario_id = auth.uid() and ar.relatorio_id = r.id)));
$$;

create or replace function central.pode_ver_relatorio_id(p_id uuid)
returns boolean language sql stable security definer set search_path = central, pg_temp as $$
  select central.usuario_ok() and (central.eh_admin()
    or exists(select 1 from central.relatorios r
              where r.id = p_id and (
                exists(select 1 from central.acessos_area aa where aa.usuario_id = auth.uid() and aa.area_id = r.area_id)
             or exists(select 1 from central.acessos_relatorio ar where ar.usuario_id = auth.uid() and ar.relatorio_id = r.id))));
$$;

-- vitrine pública da tela inicial: áreas ativas + quantidade de relatórios (sem nomes)
create or replace function central.vitrine_areas()
returns table(slug text, nome text, descricao text, icone text, cor text, ordem int, qtd_relatorios int)
language sql stable security definer set search_path = central, pg_temp as $$
  select a.slug, a.nome, a.descricao, a.icone, a.cor, a.ordem,
         (select count(*)::int from central.relatorios r where r.area_id = a.id and r.ativo)
  from central.areas a where a.ativo order by a.ordem, a.nome;
$$;

-- 1º acesso concluído (chamado logo após trocar a senha no Auth)
create or replace function central.concluir_troca_senha()
returns void language sql volatile security definer set search_path = central, pg_temp as $$
  update central.perfis set must_change_password = false where id = auth.uid();
$$;

create or replace function central.registrar_acesso()
returns void language sql volatile security definer set search_path = central, pg_temp as $$
  update central.perfis set ultimo_acesso_em = now() where id = auth.uid();
$$;

create or replace function central.set_atualizado_em()
returns trigger language plpgsql set search_path = central, pg_temp as $$
begin new.atualizado_em := now(); return new; end $$;
create or replace trigger relatorios_atualizado before update on central.relatorios
  for each row execute function central.set_atualizado_em();

-- admin não pode tirar o próprio admin nem se desativar (evita ficar sem administrador)
create or replace function central.protege_proprio_admin()
returns trigger language plpgsql set search_path = central, pg_temp as $$
begin
  if new.id = auth.uid() and (not new.is_admin or not new.ativo) then
    raise exception 'Você não pode remover o próprio acesso de administrador.';
  end if;
  return new;
end $$;
create or replace trigger perfis_protege_admin before update on central.perfis
  for each row execute function central.protege_proprio_admin();

-- ---------- privilégios ----------
revoke all on all tables in schema central from anon, authenticated;
revoke all on all functions in schema central from public, anon, authenticated;
grant select on central.areas, central.relatorios, central.perfis,
                central.acessos_area, central.acessos_relatorio, central.configuracoes to authenticated;
grant insert, update, delete on central.areas, central.relatorios,
                central.acessos_area, central.acessos_relatorio to authenticated;
grant update (nome, is_admin, ativo) on central.perfis to authenticated;
grant update (valor) on central.configuracoes to authenticated;
grant all on all tables in schema central to service_role;
grant execute on function central.vitrine_areas() to anon, authenticated;
grant execute on function central.usuario_ok(), central.eh_admin(), central.pode_ver_relatorio(text),
  central.pode_ver_relatorio_id(uuid), central.concluir_troca_senha(), central.registrar_acesso() to authenticated;
grant execute on all functions in schema central to service_role;

-- ---------- RLS ----------
alter table central.areas             enable row level security;
alter table central.relatorios        enable row level security;
alter table central.perfis            enable row level security;
alter table central.acessos_area      enable row level security;
alter table central.acessos_relatorio enable row level security;
alter table central.configuracoes     enable row level security;

create policy areas_le on central.areas for select to authenticated using (central.usuario_ok());
create policy areas_admin on central.areas for all to authenticated using (central.eh_admin()) with check (central.eh_admin());

create policy relatorios_le on central.relatorios for select to authenticated
  using (central.eh_admin() or (ativo and central.pode_ver_relatorio_id(id)));
create policy relatorios_admin on central.relatorios for all to authenticated using (central.eh_admin()) with check (central.eh_admin());

create policy perfis_le on central.perfis for select to authenticated using (id = auth.uid() or central.eh_admin());
create policy perfis_admin on central.perfis for update to authenticated using (central.eh_admin()) with check (central.eh_admin());

create policy acessos_area_le on central.acessos_area for select to authenticated using (usuario_id = auth.uid() or central.eh_admin());
create policy acessos_area_admin on central.acessos_area for all to authenticated using (central.eh_admin()) with check (central.eh_admin());

create policy acessos_rel_le on central.acessos_relatorio for select to authenticated using (usuario_id = auth.uid() or central.eh_admin());
create policy acessos_rel_admin on central.acessos_relatorio for all to authenticated using (central.eh_admin()) with check (central.eh_admin());

create policy config_admin on central.configuracoes for all to authenticated using (central.eh_admin()) with check (central.eh_admin());

-- ---------- carga inicial ----------
insert into central.areas(slug, nome, descricao, icone, cor, ordem) values
  ('rh',          'Recursos Humanos', 'Folha, rescisões, férias e indicadores de pessoal.', 'pessoas',   '#004773', 10),
  ('financeiro',  'Financeiro',       'Fluxo de caixa, contas a pagar e receber, custos.',   'moeda',     '#0b6e4f', 20),
  ('operacional', 'Operacional',      'Contratos, postos, coberturas e produtividade.',     'operacao',  '#8a5a00', 30),
  ('ti',          'T.I.',             'Chamados, sistemas, integrações e infraestrutura.',  'ti',        '#5b3f9e', 40),
  ('outros',      'Outras áreas',     'Relatórios de diretoria e demais setores.',           'pasta',     '#3c4858', 90)
on conflict (slug) do nothing;

insert into central.relatorios(area_id, slug, nome, descricao, categoria, url, ordem)
select id, 'eventos', 'Relação de Eventos — Folha Demitidos',
       'Descontos da rescisão por evento e categoria, crédito p/ saldo negativo por causa da demissão.',
       'Folha de pagamento', 'relatorios/eventos/', 10
from central.areas where slug = 'rh'
on conflict (slug) do nothing;
