-- =====================================================================
-- Contratos por Gestor (007)
-- Cadastra o relatório na área T.I. (com login; o acesso segue as
-- permissões da área/relatório). A página lê a planilha no navegador:
-- não há tabela nem dados no banco.
-- Requer 001 e 006. Aplicar no HML e na VM.
-- =====================================================================
insert into central.relatorios(area_id, slug, nome, descricao, categoria, url, ordem)
select id, 'contratos-gestores', 'Contratos por Gestor',
       'Planilha mensal de contratos agrupada por gestor e empresa, com resumos por gestor, coordenador e supervisor, para impressão.',
       'Contratos', 'relatorios/contratos-gestores/', 20
from central.areas where slug = 'ti'
on conflict (slug) do nothing;
