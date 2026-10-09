# Central de Relatórios Gerenciais — Tecnolimp

Portal interno com **login único** para os relatórios de todas as áreas (RH, Financeiro, Operacional, T.I. e outras).
Cada usuário vê só as áreas/relatórios liberados pelo administrador; a permissão é aplicada no banco (RLS), não só na tela.

## Funcionalidades
- Tela inicial por áreas, busca global (atalho `/`) e acessados recentemente
- Login por usuário de rede (ex.: `ygor.adm`), troca de senha obrigatória no 1º acesso (senha padrão única definida pelo admin)
- Página de área: busca, filtro por categoria, grade/lista, selo "Novo"
- Administração: usuários, permissões (área inteira ou relatório), áreas, relatórios, senha padrão
- Relatório **Relação de Eventos — Folha Demitidos** em `site/relatorios/eventos/`
- Relatório **Quadro de Vagas (FPRF307)** em `site/relatorios/quadro-vagas/` (área T.I.): gerado sob demanda, prévia na tela, Excel pronto para imprimir

## Estrutura
| Pasta | Conteúdo |
|---|---|
| `site/` | Frontend estático (HTML/CSS/JS, sem build). `assets/config.js` = único ponto com URL/chave do Supabase |
| `migrations/` | SQL do schema `central` (001), proteção do Painel de Eventos (002) e carga inicial da produção (003) login por usuário de rede (004) e Quadro de Vagas (005) |
| `sync/quadro-vagas/` | Worker Python da TECNOLIMP12: fila `central.qv_solicitacoes` → Oracle → resultado (ver `LEIAME.md`) |
| `supabase/functions/central-admin-usuarios/` | Edge Function: criar usuário e redefinir senha |
| `painel-redirect/` | Página que redireciona o endereço antigo do painel para a Central |

## Ambientes
| Ambiente | Banco | Site |
|---|---|---|
| HML | Supabase Cloud `Automação_relatório` (schema `central` exposto) | Vercel (este repositório, `outputDirectory: site`) |
| PROD | Supabase self-hosted `http://supabase.tecnolimp.local:8000` (VM Ubuntu tecnolimp-dados) | IIS tecnolimp15 — `http://central.apps.tecnolimp.local` |

O `config.js` versionado aponta para o HML. O pacote de produção troca só esse arquivo.

## Segurança
- Frontend usa apenas a chave anon/publishable. `service_role` nunca entra neste repositório.
- RLS em todas as tabelas do schema `central`; dados do Painel liberados só com `central.pode_ver_relatorio('eventos')`.

## Novo relatório
1. Publicar os arquivos em `site/relatorios/<pasta>/` (mesmo login, `../../assets/auth.js`).
2. Cadastrar em Administração › Relatórios (`url = relatorios/<pasta>/`).
3. Policies dos dados com `central.pode_ver_relatorio('<slug>')`.
