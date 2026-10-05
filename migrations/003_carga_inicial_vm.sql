-- =====================================================================
-- Central de Relatórios — carga inicial na produção interna (VM) (003)
-- Rodar DEPOIS do migrar-app-cloud-para-vm.sh central (só estrutura)
-- e do 002_painel_eventos_protegido.sql.
-- AJUSTE o e-mail do primeiro administrador antes de rodar.
-- =====================================================================
insert into central.configuracoes(chave, valor) values ('senha_padrao', 'Tecnolimp@2026')
on conflict (chave) do nothing;

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

-- primeiro administrador: usuário que JÁ existe no Auth da VM (ex.: o do Painel).
-- Entra com a senha que já tem (must_change_password = false).
insert into central.perfis(id, email, nome, is_admin, must_change_password)
select id, email, 'Ygor', true, false from auth.users
where lower(email) = lower('ygor.adm@tecnolimp.com.br')
on conflict (id) do update set is_admin = true, ativo = true;

select 'areas' t, count(*) from central.areas
union all select 'relatorios', count(*) from central.relatorios
union all select 'admins', count(*) from central.perfis where is_admin;
