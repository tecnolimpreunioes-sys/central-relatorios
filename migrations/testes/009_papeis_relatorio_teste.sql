-- Teste da 009: papéis por relatório (acesso x papel, admin, anon, gravação só pelo admin,
-- histórico só da diferença, trava de acesso livre). Rodar depois de 001, 004, 005, 006, 007, 008 e 009.
-- Erros listados em "erros esperados" são o comportamento correto.
\set ON_ERROR_STOP 0
\pset footer off
-- usuários: adm (admin), area (RH inteira, sem papel), rel (só o relatório, papel editor),
--           dois (RH inteira, papéis leitor e editor), fora (papel leitor, mas sem acesso ao relatório)
insert into auth.users values
 ('a0000000-0000-0000-0000-000000000000','adm@x'), ('a1111111-1111-1111-1111-111111111111','area@x'),
 ('a2222222-2222-2222-2222-222222222222','rel@x'), ('a3333333-3333-3333-3333-333333333333','dois@x'),
 ('a4444444-4444-4444-4444-444444444444','fora@x');
insert into central.perfis(id,email,login,is_admin,must_change_password) values
 ('a0000000-0000-0000-0000-000000000000','adm@x','adm.teste',true,false),
 ('a1111111-1111-1111-1111-111111111111','area@x','area.teste',false,false),
 ('a2222222-2222-2222-2222-222222222222','rel@x','rel.teste',false,false),
 ('a3333333-3333-3333-3333-333333333333','dois@x','dois.teste',false,false),
 ('a4444444-4444-4444-4444-444444444444','fora@x','fora.teste',false,false);
insert into central.relatorios(area_id, slug, nome, url)
select id, 'teste-papeis', 'Teste de papéis', 'relatorios/teste-papeis/' from central.areas where slug = 'rh';
insert into central.relatorio_papeis(relatorio_id, papel, nome, ordem)
select id, p, initcap(p), o from central.relatorios, (values ('leitor',10),('editor',20)) v(p,o) where slug = 'teste-papeis';
insert into central.acessos_area select u, id from central.areas,
 (values ('a1111111-1111-1111-1111-111111111111'::uuid),('a3333333-3333-3333-3333-333333333333'::uuid)) v(u) where slug = 'rh';
insert into central.acessos_relatorio select 'a2222222-2222-2222-2222-222222222222', id from central.relatorios where slug = 'teste-papeis';
select id as rid from central.relatorios where slug = 'teste-papeis' \gset

\echo '--- 1. admin grava papéis'
set role authenticated; set request.jwt.claim.role='authenticated'; set request.jwt.claim.sub='a0000000-0000-0000-0000-000000000000';
select central.salvar_papeis('a2222222-2222-2222-2222-222222222222', format('[{"relatorio_id":"%s","papel":"editor"}]', :'rid')::jsonb);
select central.salvar_papeis('a3333333-3333-3333-3333-333333333333', format('[{"relatorio_id":"%s","papel":"leitor"},{"relatorio_id":"%s","papel":"editor"}]', :'rid', :'rid')::jsonb);
select central.salvar_papeis('a4444444-4444-4444-4444-444444444444', format('[{"relatorio_id":"%s","papel":"leitor"}]', :'rid')::jsonb);
select count(*) as papeis_gravados from central.acessos_papel;

\echo '--- 2. papéis de cada um (esperado: adm {leitor,editor} | area {} | rel {editor} | dois {leitor,editor} | fora {} sem acesso)'
select 'adm' as quem, central.meus_papeis('teste-papeis') as papeis, central.relatorio_contexto('teste-papeis') as ctx;
set request.jwt.claim.sub='a1111111-1111-1111-1111-111111111111';
select 'area' as quem, central.meus_papeis('teste-papeis') as papeis, central.relatorio_contexto('teste-papeis') as ctx;
set request.jwt.claim.sub='a2222222-2222-2222-2222-222222222222';
select 'rel' as quem, central.meus_papeis('teste-papeis') as papeis, central.tem_papel('teste-papeis','leitor') as tem_leitor, central.tem_papel('teste-papeis','editor') as tem_editor;
set request.jwt.claim.sub='a3333333-3333-3333-3333-333333333333';
select 'dois' as quem, central.meus_papeis('teste-papeis') as papeis;
set request.jwt.claim.sub='a4444444-4444-4444-4444-444444444444';
select 'fora' as quem, central.meus_papeis('teste-papeis') as papeis, central.relatorio_contexto('teste-papeis') as ctx;
\echo '   papel inexistente (esperado: f mesmo para admin)'
set request.jwt.claim.sub='a0000000-0000-0000-0000-000000000000';
select central.tem_papel('teste-papeis','x') as adm_papel_x;

\echo '--- 3. quem não é admin não grava (erros esperados) e só lê o que é seu'
set request.jwt.claim.sub='a3333333-3333-3333-3333-333333333333';
select central.salvar_papeis('a3333333-3333-3333-3333-333333333333', '[]');
insert into central.acessos_papel values ('a1111111-1111-1111-1111-111111111111', :'rid', 'leitor');
select count(*) as linhas_visiveis_dois from central.acessos_papel;
select count(*) as log_visivel_dois from central.acessos_papel_log;

\echo '--- 4. anon (esperado: pode_ver false; tem_papel sem permissão = erro esperado)'
reset role; set role anon; set request.jwt.claim.role='anon'; set request.jwt.claim.sub='';
select central.relatorio_contexto('teste-papeis');
select central.tem_papel('teste-papeis','leitor');
reset role;

\echo '--- 5. histórico: regravar igual não gera linha; tirar editor do dois gera 1 "removido"'
set role authenticated; set request.jwt.claim.role='authenticated'; set request.jwt.claim.sub='a0000000-0000-0000-0000-000000000000';
select count(*) as log_antes from central.acessos_papel_log;
select central.salvar_papeis('a3333333-3333-3333-3333-333333333333', format('[{"relatorio_id":"%s","papel":"leitor"},{"relatorio_id":"%s","papel":"editor"}]', :'rid', :'rid')::jsonb);
select count(*) as log_igual from central.acessos_papel_log;
select central.salvar_papeis('a3333333-3333-3333-3333-333333333333', format('[{"relatorio_id":"%s","papel":"leitor"}]', :'rid')::jsonb);
select por_login, usuario_login, relatorio_slug, papel, acao from central.acessos_papel_log order by id;
\echo '   papel fora do catálogo (erro esperado: FK)'
select central.salvar_papeis('a3333333-3333-3333-3333-333333333333', format('[{"relatorio_id":"%s","papel":"zz"}]', :'rid')::jsonb);

\echo '--- 6. relatório inativo: ninguém tem papel (esperado: f)'
reset role; update central.relatorios set ativo = false where slug = 'teste-papeis';
set role authenticated; set request.jwt.claim.sub='a2222222-2222-2222-2222-222222222222';
select central.tem_papel('teste-papeis','editor') as rel_editor_inativo;
reset role; update central.relatorios set ativo = true where slug = 'teste-papeis';

\echo '--- 7. trava de acesso livre (2 erros esperados) e relatório sem papéis segue livre (UPDATE sem erro)'
update central.relatorios set publico = true where slug = 'teste-papeis';
insert into central.relatorio_papeis(relatorio_id, papel, nome)
select id, 'leitor', 'Leitor' from central.relatorios where slug = 'quadro-vagas' and publico;
update central.relatorios set publico = true where slug = 'eventos';
update central.relatorios set publico = false where slug = 'eventos';

\echo '--- 8. excluir o relatório apaga catálogo e papéis e o histórico fica (esperado: 0 | 0 | >0)'
delete from central.relatorios where slug = 'teste-papeis';
select (select count(*) from central.relatorio_papeis) as catalogo, (select count(*) from central.acessos_papel) as papeis,
       (select count(*) from central.acessos_papel_log) as historico;
