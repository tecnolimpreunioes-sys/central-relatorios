-- =====================================================================
-- Relação de Eventos (Painel de Rescisões, schema public — legado) (002)
-- Leitura só para usuário logado na Central com acesso ao relatório
-- "eventos". Configuração de eventos só para admin da Central.
-- O sync (service_role) não é afetado: ignora RLS.
-- Requer 001_central_schema.sql aplicado antes.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['painel_resumo','painel_eventos_valores','painel_credito_causas',
                           'config_eventos','config_empresas','integracao_auditoria'] loop
    execute format('revoke select on public.%I from anon', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ALTER POLICY (sem DROP): troca papel e regra das policies de leitura existentes
alter policy painel_resumo_select on public.painel_resumo to authenticated
  using (central.pode_ver_relatorio('eventos'));
alter policy painel_eventos_valores_select on public.painel_eventos_valores to authenticated
  using (central.pode_ver_relatorio('eventos'));
alter policy leitura_publica_credito_causas on public.painel_credito_causas to authenticated
  using (central.pode_ver_relatorio('eventos'));
alter policy config_eventos_select on public.config_eventos to authenticated
  using (central.pode_ver_relatorio('eventos'));
alter policy config_empresas_select on public.config_empresas to authenticated
  using (central.pode_ver_relatorio('eventos'));
alter policy integracao_auditoria_select on public.integracao_auditoria to authenticated
  using (central.pode_ver_relatorio('eventos'));
-- escrita direta nas configs: só admin da Central (a tela usa as RPCs abaixo)
alter policy config_eventos_write on public.config_eventos to authenticated
  using (central.eh_admin()) with check (central.eh_admin());
alter policy config_empresas_write on public.config_empresas to authenticated
  using (central.eh_admin()) with check (central.eh_admin());

-- RPCs da tela Configurações: agora exigem admin da Central
create or replace function public.painel_exige_admin()
returns void language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not central.eh_admin() then raise exception 'Acesso restrito ao administrador.'; end if;
end $$;

create or replace function public.painel_adicionar_evento(p_codigo text, p_categoria text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cod text := regexp_replace(coalesce(p_codigo,''), '\s', '', 'g');
        v_cat text := btrim(coalesce(p_categoria,''));
begin
  perform public.painel_exige_admin();
  if v_cod = '' or v_cat = '' then raise exception 'Código e categoria são obrigatórios'; end if;
  if v_cod !~ '^\d{1,6}(,\d{1,6}){0,19}$' then raise exception 'Código inválido'; end if;
  if length(v_cat) > 60 then raise exception 'Categoria muito longa'; end if;
  if exists(select 1 from config_eventos where codigo = v_cod) then raise exception 'Código já cadastrado'; end if;
  insert into config_eventos(codigo, categoria, mais_usado, ativo) values (v_cod, v_cat, false, true);
end $$;

create or replace function public.painel_ativar_evento(p_codigo text, p_ativo boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.painel_exige_admin();
  update config_eventos set ativo = coalesce(p_ativo, true) where codigo = p_codigo;
end $$;

create or replace function public.painel_editar_evento(p_codigo_atual text, p_codigo_novo text, p_categoria text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_cod text := regexp_replace(coalesce(p_codigo_novo,''), '\s', '', 'g');
        v_cat text := btrim(coalesce(p_categoria,''));
begin
  perform public.painel_exige_admin();
  if v_cod = '' or v_cat = '' then raise exception 'Código e categoria são obrigatórios'; end if;
  if v_cod !~ '^\d{1,6}(,\d{1,6}){0,19}$' then raise exception 'Código inválido'; end if;
  if length(v_cat) > 60 then raise exception 'Categoria muito longa'; end if;
  if not exists(select 1 from config_eventos where codigo = p_codigo_atual) then raise exception 'Evento não encontrado'; end if;
  if v_cod <> p_codigo_atual and exists(select 1 from config_eventos where codigo = v_cod) then raise exception 'Código já cadastrado'; end if;
  update config_eventos set codigo = v_cod, categoria = v_cat where codigo = p_codigo_atual;
  -- remove o detalhamento antigo; o próximo sync regrava com o código/categoria novos
  if v_cod <> p_codigo_atual then delete from painel_eventos_valores where evento_codigo = p_codigo_atual; end if;
  update painel_eventos_valores set categoria = v_cat where evento_codigo = v_cod;
end $$;

revoke all on function public.painel_exige_admin(), public.painel_adicionar_evento(text,text),
  public.painel_ativar_evento(text,boolean), public.painel_editar_evento(text,text,text) from public, anon;
grant execute on function public.painel_adicionar_evento(text,text),
  public.painel_ativar_evento(text,boolean), public.painel_editar_evento(text,text,text) to authenticated;

-- funções legadas / internas: sem execução pelo navegador
revoke execute on function public.set_atualizado_em() from public, anon, authenticated;
revoke execute on function public.eh_admin_painel() from public, anon, authenticated;
revoke execute on function public.painel_exige_admin() from public, anon, authenticated;
