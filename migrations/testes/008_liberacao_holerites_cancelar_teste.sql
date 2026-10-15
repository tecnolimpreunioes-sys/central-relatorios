-- Teste da 008 (rodar depois do teste da 007, no mesmo banco):
-- TI cancela pedido na fila; pedido já com o integrador não é cancelado; RH sem acesso não cancela.
\set ON_ERROR_STOP 0
\pset footer off
set role authenticated; set request.jwt.claim.role='authenticated'; set request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
\echo '--- 1. cancela pendente -> cancelado'
select central.lh_cancelar(central.lh_solicitar('atualizar')) as status;
select status, mensagem from central.lh_pedidos order by criado_em desc limit 1;
\echo '--- 2. pedido já processando segue (esperado: processando)'
select central.lh_solicitar('atualizar') as id \gset
reset role; update central.lh_pedidos set status = 'processando' where id = :'id';
set role authenticated; set request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
select central.lh_cancelar(:'id') as status;
\echo '--- 3. RH sem acesso (erro esperado) e id inexistente (erro esperado)'
set request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
select central.lh_cancelar(:'id');
set request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
select central.lh_cancelar(gen_random_uuid());
reset role;
