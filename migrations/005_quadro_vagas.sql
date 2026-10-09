-- =====================================================================
-- Quadro de Vagas (FPRF307 — Relação de Funcionários) (005)
-- Geração sob demanda: a tela grava a solicitação; o worker da TECNOLIMP12
-- (service_role) pega a próxima da fila, consulta o Oracle e grava o
-- resultado na mesma linha. Nada é agendado; só roda quando alguém clica
-- em Gerar. O resultado não tem dado pessoal (só quantidades por cargo).
-- Requer 001_central_schema.sql. Aplicar no HML e na VM.
-- =====================================================================
create table if not exists central.qv_solicitacoes (
  id            uuid primary key default gen_random_uuid(),
  usuario_id    uuid not null default auth.uid() references central.perfis(id) on delete cascade,
  data_emissao  date not null,
  empresas      text not null check (empresas ~ '^\d{1,4}(-\d{1,4})?(,\d{1,4}(-\d{1,4})?)*$' and length(empresas) <= 100),
  locais        text not null default '' check (locais ~ '^(\d+(\.\d+)*(==)?(,\d+(\.\d+)*(==)?)*)?$' and length(locais) <= 300),
  status        text not null default 'pendente' check (status in ('pendente','processando','concluido','erro')),
  mensagem      text,
  resultado     jsonb,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index if not exists qv_solicitacoes_fila_idx on central.qv_solicitacoes (criado_em) where status = 'pendente';
create index if not exists qv_solicitacoes_usuario_idx on central.qv_solicitacoes (usuario_id, criado_em desc);

-- usuário só cria solicitação "pendente" em nome próprio, no máximo 3 abertas por vez
create or replace function central.qv_antes_inserir()
returns trigger language plpgsql security definer set search_path = central, pg_temp as $$
begin
  if auth.role() = 'service_role' then return new; end if;
  new.usuario_id := auth.uid();
  new.status := 'pendente'; new.mensagem := null; new.resultado := null;
  new.criado_em := now(); new.atualizado_em := now();
  if (select count(*) from central.qv_solicitacoes s
      where s.usuario_id = auth.uid() and s.status in ('pendente','processando')) >= 3 then
    raise exception 'Aguarde a conclusão das gerações em andamento.';
  end if;
  return new;
end $$;
create or replace trigger qv_solicitacoes_antes_inserir before insert on central.qv_solicitacoes
  for each row execute function central.qv_antes_inserir();

-- worker: pega a próxima pendente (uma por vez, sem disputa entre instâncias)
create or replace function central.qv_proxima()
returns setof central.qv_solicitacoes language sql volatile security definer set search_path = central, pg_temp as $$
  update central.qv_solicitacoes s set status = 'processando', atualizado_em = now()
  where s.id = (select id from central.qv_solicitacoes
                where status = 'pendente' order by criado_em limit 1 for update skip locked)
  returning s.*;
$$;

-- worker: encerra travadas (>10 min) e apaga o histórico com mais de 7 dias
create or replace function central.qv_manutencao()
returns void language sql volatile security definer set search_path = central, pg_temp as $$
  update central.qv_solicitacoes set status = 'erro', mensagem = 'Tempo esgotado no serviço de geração.', atualizado_em = now()
  where status in ('pendente','processando') and atualizado_em < now() - interval '10 minutes';
  delete from central.qv_solicitacoes where criado_em < now() - interval '7 days';
$$;

revoke all on function central.qv_proxima(), central.qv_manutencao() from public, anon, authenticated;
grant execute on function central.qv_proxima(), central.qv_manutencao() to service_role;

grant select on central.qv_solicitacoes to authenticated;
grant insert (data_emissao, empresas, locais) on central.qv_solicitacoes to authenticated;
grant all on central.qv_solicitacoes to service_role;

alter table central.qv_solicitacoes enable row level security;
create policy qv_le on central.qv_solicitacoes for select to authenticated
  using (usuario_id = auth.uid() and central.pode_ver_relatorio('quadro-vagas'));
create policy qv_cria on central.qv_solicitacoes for insert to authenticated
  with check (usuario_id = auth.uid() and central.pode_ver_relatorio('quadro-vagas'));

-- cadastro na Central (área T.I.)
insert into central.relatorios(area_id, slug, nome, descricao, categoria, url, ordem)
select id, 'quadro-vagas', 'Quadro de Vagas — Relação de Funcionários',
       'Formulário por local e cargo (FPRF307) com autorizado x efetivo, para impressão e preenchimento manual.',
       'Pessoal', 'relatorios/quadro-vagas/', 10
from central.areas where slug = 'ti'
on conflict (slug) do nothing;
