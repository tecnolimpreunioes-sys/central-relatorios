-- =====================================================================
-- Liberação de holerites RH 24h (008): cancelar pedido pelo painel
-- Só cancela pedido ainda na fila (pendente). Se o integrador já pegou
-- (processando), a alteração segue e se desfaz depois pelo próprio painel.
-- Requer 007. Pode rodar de novo sem efeito colateral.
-- =====================================================================

alter table central.lh_pedidos drop constraint if exists lh_pedidos_status_check;
alter table central.lh_pedidos add constraint lh_pedidos_status_check
  check (status in ('pendente','processando','aplicado','erro','cancelado'));

-- devolve o status final: 'cancelado' ou o status em que o pedido já estava
create or replace function central.lh_cancelar(p_id uuid)
returns text language plpgsql volatile security definer set search_path = central, pg_temp as $$
declare v_status text; v_login text;
begin
  if not central.lh_pode() then
    raise exception 'Sem acesso à liberação de holerites.' using errcode = '42501';
  end if;
  select p.login into v_login from central.perfis p where p.id = auth.uid();
  update central.lh_pedidos
     set status = 'cancelado', mensagem = left('Cancelado por ' || coalesce(v_login, '?'), 200), atualizado_em = now()
   where id = p_id and status = 'pendente'
  returning status into v_status;
  if v_status is null then
    select status into v_status from central.lh_pedidos where id = p_id;
    if v_status is null then raise exception 'Pedido não encontrado.'; end if;
  end if;
  return v_status;
end $$;

-- limpeza de 90 dias passa a levar os cancelados
create or replace function central.lh_manutencao()
returns void language sql volatile security definer set search_path = central, pg_temp as $$
  update central.lh_pedidos set status = 'erro', mensagem = 'Tempo esgotado no integrador.', atualizado_em = now()
  where status = 'processando' and atualizado_em < now() - interval '10 minutes';
  update central.lh_pedidos set status = 'erro', mensagem = 'Expirado: o integrador ficou fora do ar. Refaça o pedido.', atualizado_em = now()
  where status = 'pendente' and criado_em < now() - interval '1 day';
  delete from central.lh_pedidos where criado_em < now() - interval '90 days' and status in ('aplicado','erro','cancelado');
$$;

revoke all on function central.lh_cancelar(uuid) from public, anon;
grant execute on function central.lh_cancelar(uuid) to authenticated, service_role;
