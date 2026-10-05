-- =====================================================================
-- Central de Relatórios — login por usuário de rede (ex.: ygor.adm) (004)
-- O Supabase Auth continua usando e-mail por baixo; a tela de login
-- converte o usuário de rede no e-mail via central.email_para_login().
-- Usuário sem e-mail corporativo recebe <login>@usuarios.tecnolimp.local.
-- =====================================================================
alter table central.perfis add column if not exists login text;
update central.perfis set login = lower(split_part(email, '@', 1)) where login is null;
alter table central.perfis alter column login set not null;
alter table central.perfis add constraint perfis_login_formato check (login ~ '^[a-z0-9._-]{2,40}$');
create unique index if not exists perfis_login_uk on central.perfis (login);

create or replace function central.email_para_login(p_login text)
returns text language sql stable security definer set search_path = central, pg_temp as $$
  select p.email from central.perfis p where p.login = lower(btrim(p_login)) and p.ativo limit 1;
$$;
revoke all on function central.email_para_login(text) from public;
grant execute on function central.email_para_login(text) to anon, authenticated, service_role;
grant update (login) on central.perfis to authenticated;
