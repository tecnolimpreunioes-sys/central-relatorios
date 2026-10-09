# Central de Relatórios Gerenciais — Tecnolimp

Portal interno com **login único** para os relatórios de todas as áreas (RH, Financeiro, Operacional, T.I. e outras).
Cada usuário vê só as áreas/relatórios liberados pelo administrador; a permissão é aplicada no banco (RLS), não só na tela.

## Funcionalidades
- Tela inicial por áreas, busca global (atalho `/`) e acessados recentemente
- Login por usuário de rede (ex.: `ygor.adm`), troca de senha obrigatória no 1º acesso (senha padrão única definida pelo admin)
- Página de área: busca, filtro por categoria, grade/lista, selo "Novo"
- Administração: usuários, permissões (área inteira ou relatório), áreas, relatórios, senha padrão

## Relatórios
| Relatório | Área | Pasta | Dados |
|---|---|---|---|
| Relação de Eventos — Folha Demitidos | RH | `site/relatorios/eventos/` | Sync agendado Oracle → Supabase |
| Quadro de Vagas (FPRF307) | T.I. | `site/relatorios/quadro-vagas/` | **Sob demanda**: worker consulta o Oracle ao clicar em Gerar |

### Quadro de Vagas (FPRF307)
Formulário por local e cargo para impressão e preenchimento à caneta.
- **Filtros:** Empresa (`3`, `1,3`, `1-5`) e Local (`3.111.1.1` ou `3.111==` = o local e todos abaixo). Data sempre a do dia.
- **Conteúdo:** totais gerais (colaboradores = autorizado + efetivo), local (nome, código, endereço), cargo, quadro **Autorizado × Efetivo** (competência do mês atual, como no Senior) e linhas em branco: uma por colaborador ativo; cargos do quadro do mês sem colaborador (vagas em aberto, posto novo) também saem, com uma linha por vaga autorizada.
- **Saídas:** prévia na tela igual ao papel, **Imprimir** e **Exportar Excel** (`quadro de vagas - dd-mm-aaaa.xlsx`, A4 paisagem, cabeçalho repetido, "Página X de Y", cada local em página nova).
- **Fluxo:** tela grava em `central.qv_solicitacoes` → worker da TECNOLIMP12 (`sync/quadro-vagas/`) consulta o Oracle e grava o resultado → tela exibe. Resultado só com quantidades (sem dados pessoais); retenção de 7 dias.
- Documentação técnica completa: [`docs/quadro-de-vagas-documentacao-tecnica.pdf`](docs/quadro-de-vagas-documentacao-tecnica.pdf).

## Estrutura
| Pasta | Conteúdo |
|---|---|
| `site/` | Frontend estático (HTML/CSS/JS, sem build). `assets/config.js` = único ponto com URL/chave do Supabase |
| `site/assets/vendor/` | Bibliotecas servidas localmente (ExcelJS 4.4.0) |
| `migrations/` | SQL do schema `central`: base (001), proteção do Painel de Eventos (002), carga inicial da produção (003), login por usuário de rede (004) e Quadro de Vagas (005) |
| `sync/quadro-vagas/` | Worker Python da TECNOLIMP12 (fila → Oracle → resultado) e instalação no Agendador — ver `LEIAME.md` |
| `supabase/functions/central-admin-usuarios/` | Edge Function: criar usuário e redefinir senha |
| `painel-redirect/` | Página que redireciona o endereço antigo do painel para a Central |
| `docs/` | Documentação técnica (PDF) |

## Ambientes
| Ambiente | Banco | Site | Scripts Oracle |
|---|---|---|---|
| HML | Supabase Cloud `Automação_relatório` (schema `central` exposto) | Vercel (este repositório, `outputDirectory: site`) | — |
| PROD | Supabase self-hosted `http://supabase.tecnolimp.local:8000` (VM Ubuntu tecnolimp-dados) | IIS tecnolimp15 — `http://central.apps.tecnolimp.local` (`C:\Sites\central`) | TECNOLIMP12 (Agendador) |

O `config.js` versionado aponta para o HML. O pacote de produção troca só esse arquivo.

## Operação (PROD)
- **Migration nova:** aplicar na VM Ubuntu como dono do schema (o SQL Editor do Studio não tem permissão no `central`):
  ```bash
  sudo docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < ~/NNN_arquivo.sql
  ```
- **Site:** copiar os arquivos para `C:\Sites\central` (`robocopy <pasta> C:\Sites\central /E`), sem sobrescrever o `config.js` da produção.
- **Worker Quadro de Vagas:** tarefa "Tecnolimp - Quadro de Vagas (worker)" na TECNOLIMP12; log em `sync\quadro-vagas\logs\worker_quadro_vagas.log`. Credenciais no `credenciais.bat` local (chama a fonte única do sync; nunca versionado).

## Segurança
- Frontend usa apenas a chave anon/publishable. `service_role` só no `credenciais.bat` da TECNOLIMP12, nunca neste repositório.
- RLS em todas as tabelas do schema `central`; dados liberados só com `central.pode_ver_relatorio('<slug>')`.
- Oracle/Sapiens somente leitura, acessado apenas pelos scripts da TECNOLIMP12 (consultas parametrizadas).

## Novo relatório
1. Publicar os arquivos em `site/relatorios/<pasta>/` (mesmo login, `../../assets/auth.js`).
2. Cadastrar em Administração › Relatórios (`url = relatorios/<pasta>/`) ou na própria migration.
3. Policies dos dados com `central.pode_ver_relatorio('<slug>')`.
4. Precisa consultar o Oracle sob demanda? Reaproveitar o padrão do Quadro de Vagas (fila + worker).
