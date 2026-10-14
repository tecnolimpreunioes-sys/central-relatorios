-- Teste da 007: permissões (TI / sem acesso / anon), validações do lh_solicitar,
-- fluxo do worker, histórico "painel" x "fora do painel" e trava de acesso livre.
-- Erros listados em "erros esperados" e nas seções 3, 4 e 8 são o comportamento correto.
\set ON_ERROR_STOP 0
\pset footer off
-- usuários: ti (área T.I.), rh (sem acesso)
insert into auth.users values ('11111111-1111-1111-1111-111111111111','ti@x'),('22222222-2222-2222-2222-222222222222','rh@x');
insert into central.perfis(id,email,login,must_change_password) values
 ('11111111-1111-1111-1111-111111111111','ti@x','ygor.adm',false),('22222222-2222-2222-2222-222222222222','rh@x','dayane.rh',false);
insert into central.acessos_area select '11111111-1111-1111-1111-111111111111', id from central.areas where slug='ti';

\echo '--- 1. worker espelha (1a leitura)'
set role service_role; set request.jwt.claim.role='service_role';
select central.lh_espelhar('2026-07-01',
 '[{"emp":3,"per":"2026-09-01","codcal":512,"datpag":"2026-10-06"},{"emp":5,"per":"2026-09-01","codcal":513,"datpag":"2026-10-15"},{"emp":3,"per":"2026-08-01","codcal":500,"datpag":"2026-09-04"}]',
 '[{"emp":3,"per":"2026-08-01","sit":1,"ini":"2026-09-03","usu":"VIRADA","gra":"2026-10-13","obs":"Virada"}]') as alteracoes_fora;
reset role;

\echo '--- 2. TI le e pede'
set role authenticated; set request.jwt.claim.role='authenticated'; set request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
select count(*) as folhas_visiveis from central.lh_folhas;
select central.lh_solicitar('liberar','[{"emp":3,"per":"2026-09-01"},{"emp":3,"per":"2026-09-01"}]') is not null as pedido_ok;
select alvos, data_ini = central.lh_hoje() as ini_hoje, usuario_login from central.lh_pedidos;
\echo '   erros esperados:'
select central.lh_solicitar('bloquear','[{"emp":3,"per":"2026-09-01"}]');
select central.lh_solicitar('agendar','[{"emp":3,"per":"2026-09-01"}]', current_date - 1);
select central.lh_solicitar('liberar','[{"emp":9,"per":"2026-09-01"}]');
select central.lh_solicitar('liberar','[{"emp":"x","per":"2026"}]');
select central.lh_solicitar('liberar','[]');
select central.lh_solicitar('apagar_tudo','[]');
insert into central.lh_pedidos(usuario_login,acao) values ('ygor.adm','liberar');
update central.lh_liberacoes set sit_lib=1;
select central.lh_proximo();

\echo '--- 3. RH sem acesso'
set request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
select count(*) as folhas_rh from central.lh_folhas;
select count(*) as log_rh from central.lh_log;
select central.lh_solicitar('atualizar');

\echo '--- 4. anon'
reset role; set role anon; set request.jwt.claim.role='anon'; set request.jwt.claim.sub='';
select count(*) from central.lh_folhas;
select central.lh_solicitar('atualizar');
reset role;

\echo '--- 5. worker aplica'
set role service_role; set request.jwt.claim.role='service_role';
select id as pid from central.lh_proximo() \gset
select central.lh_concluir(:'pid','aplicado',null,
  format('[{"emp":3,"per":"2026-09-01","sit":1,"ini":"%s","gra":"%s"}]', central.lh_hoje(), central.lh_hoje())::jsonb);
select status from central.lh_pedidos where id=:'pid';
select usuario, num_emp, per_ref, acao, de, para, origem from central.lh_log order by id;

\echo '--- 6. releitura igual: 0 alteracoes fora do painel (nao duplica)'
select central.lh_espelhar('2026-07-01',
 '[{"emp":3,"per":"2026-09-01","codcal":512,"datpag":"2026-10-06"},{"emp":5,"per":"2026-09-01","codcal":513,"datpag":"2026-10-15"},{"emp":3,"per":"2026-08-01","codcal":500,"datpag":"2026-09-04"}]',
 format('[{"emp":3,"per":"2026-08-01","sit":1,"ini":"2026-09-03","usu":"VIRADA","gra":"2026-10-13","obs":"Virada"},{"emp":3,"per":"2026-09-01","sit":1,"ini":"%s","usu":"ygor.adm","gra":"%s","obs":""}]', central.lh_hoje(), central.lh_hoje())::jsonb) as alteracoes_fora;

\echo '--- 7. contingencia: SQL bloqueou 3/ago e apagou 3/set direto no Oracle'
select central.lh_espelhar('2026-07-01',
 '[{"emp":3,"per":"2026-09-01","codcal":512,"datpag":"2026-10-06"}]',
 '[{"emp":3,"per":"2026-08-01","sit":0,"ini":"2026-09-03","usu":"ygor.adm","gra":"2026-10-14","obs":"Recalculo"}]') as alteracoes_fora;
select usuario, num_emp, per_ref, acao, de, para, origem from central.lh_log where origem='fora_do_painel' order by id;
select central.lh_manutencao();
reset role;

\echo '--- 8. nao pode virar acesso livre'
update central.relatorios set publico = true where slug='liberacao-holerites';
