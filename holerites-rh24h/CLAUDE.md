# Holerites RH 24h — Tecnolimp (Senior Rubi / Gestão de Pessoas 6.10.4.134)

Contexto de continuidade. Ler este arquivo inteiro antes de agir; detalhe do plano em `docs/plano-liberacao.md`.

## O que é
- 15 modelos do Modelo Gerador (LSP) que geram o holerite do portal **RH 24h** (rubiweb, conector `conector?ACAO=ENTRANCEREL&SIS=FP&NOME=FPFFx9y.OPE`).
- Nome: `FPFF{site}9{pos}` — site 4,5,6,7,8; pos 1 = mês M-1, 2 = M-2, 3 = M-3 (combo do portal: holerite / holerite_anterior / holerite_posterior).
- Login do colaborador = cadastro + sufixo da empresa: nenhum=1, E=3, P=3, S=4, D=5, L=6, S7=7, J=8 (futuro), Y=9.

## Status
| Fase | Situação |
|---|---|
| 1. Competência automática + liberação D-1 do pagamento | **Concluída e validada** no FPFF996 (Juliana 36725E, emp. 3, ago/2026, líquido 463,99). Código: `sapiens/preselecao_fase1_validada.txt`. Falta replicar nos 15 em PRD |
| 2. Supabase (espelho + fila + log + RLS) | **Aplicada e testada no HML** (14/10): `migrations/007_liberacao_holerites.sql` (+ `migrations/testes/`). Falta a VM. Obs.: o conector Supabase não aplica SQL com `delete` (pede confirmação) — esse trecho vai pelo SQL Editor |
| 3. Integrador Python (TECNOLIMP12) | **Pronto e testado sem Oracle** (14/10): `sync/liberacao-holerites/` (teste ponta a ponta com Sapiens falso + funções reais). Falta: usuário Oracle dedicado (`sapiens/usuario_integrador.sql`), `--diagnostico`/`--leitura` na TECNOLIMP12 depois que a `USU_TLIBHOL` existir |
| 4. Painel na Central | **Pronto e testado com Supabase simulado** (14/10): `site/relatorios/liberacao-holerites/` (index + painel.js + painel.css). Permissão por `lh_pode()` (não usa `relatorio_contexto`, que falta no HML). Falta: dados reais no HML (integrador `--espelhar` apontando para o HML) e teste ponta a ponta |
| Portal `index.html` | **Validado no piloto (14/10)**: próximo mês "Em breve", 3 meses do portal com selo "Em breve" / "Sem holerite", pedidos em fila |
| Piloto ServiPlus (4) + Servinews (7) | **Validado em produção (14/10)**: modelos 491/492/493 com o bloco 6 + virada. Demais empresas prontas em `sapiens/producao/` (12 pré-seleções + `virada_demais_empresas.sql`) |
| 2. Liberação manual (padrão bloqueado, TI libera) | **Bloco 6 validado no FPFF996 em 14/10** (T1–T5 ok com o 628S7: sem linha / agendado amanhã / bloqueado não emitem; liberado hoje emite). Decisões: `docs/plano-liberacao.md`. Arquivos: `sapiens/preselecao_fase2_liberacao.txt` (bloco 6), `sapiens/USU_TLIBHOL.md`, `sapiens/sql_contingencia.sql`, roteiro executável `sapiens/teste_fase1.sql`. Teste da Fase 2 no FPFF996 com o usuário **628S7** (empresa 7 ServiPlus, parâmetros do site 49x: `aHolSite "4,7"`, ago/2026); `USU_TLIBHOL` criada e conferida em 14/10. Protótipo do painel: `prototipos/liberacao-holerites.html` |

## Parâmetros por modelo (pré-seleção genérica, só 3 linhas mudam)
Chamar os grupos de modelos **pelo nome da empresa** (pedido do Ygor), não por "49x".
| Modelos | Empresas (R030EMP) | `aHolSite` | `nHolAviso` |
|---|---|---|---|
| FPFF491/492/493 | ServiPlus (4) + ServiPlus Terceirizados / Servinews (7) | "4,7" | 1 |
| FPFF591/592/593 | Pontual (3) | "3" | 1 |
| FPFF691/692/693 | Tecnolimp (1) (+ 9, que não existe na R030EMP) | "1,9" | 1 |
| FPFF791/792/793 | Deltalimp (6) | "6" | 0 |
| FPFF891/892/893 | DRA (5) | "5" | 0 |
`nHolAtras` = último dígito do modelo (1/2/3). Buscar por `nHolAtras =`, `aHolSite  =`, `nHolAviso =`. Linha `TESTE - REMOVER` só existe no 996 — apagar em PRD.
Empresa 8: quando entrar, incluir `8` no `aHolSite` do site que a atender.

## Gotchas LSP (já custaram tempo — não redescobrir)
- `@` dentro de comentário fecha o comentário (engoliu código e gerou ORA-01722).
- Variável Alfa ligada a coluna numérica em `.Sql` → ORA-01722. Usar Numero (`xCadNum`).
- Conflito de tipo no catálogo → prefixo próprio nas variáveis (`Hol...`).
- Sem alias de tabela em cursor; JOIN/UNION sem garantia (Senior SQL 2); preferir dois cursores simples a subquery.
- "Consistir Modelo" varre literais por `TABELA.CAMPO`: em cursor de tabela sem relacionamento, escrever campos sem prefixo.
- `IntParaAlfa` não aceita campo de cursor direto: passar por variável Numero.
- `Mensagem(Retorna, ...)` não aceita expressão (`"txt" + var` → "falta )"): montar o texto numa variável Alfa antes.
- Escrita: `ExecSql "UPDATE ... WHERE X = :vVar";` com binds (exemplo oficial Senior, regra 611).
- `Cancel(1)` na pré-seleção = não emite. Rodar com login admin não emite (não é colaborador) — testar com a linha de override.
- R044CAL: `PerRef` sempre dia 01; `DatPag` = pagamento; `TipCal = 11` folha mensal.

## Regras Tecnolimp que se aplicam
- Oracle/Sapiens só leitura; frontend nunca acessa Oracle; escrita no Senior só por web service — exceção para a `USU_TLIBHOL` depende de aprovação (decisão 1 do plano).
- Relatório da Central sempre nasce com a opção "pede senha?" (006); este **sempre pede** (trigger `lh_exige_login` + `lh_pode` ignora acesso livre): cada ação registra o usuário.
- Painéis internos moram na **Central de Relatórios** (`central.apps.tecnolimp.local`, schema `central`, login por usuário de rede). Skills: `tecnolimp-contexto-base`, `relatorio-web-tecnolimp`, `tecnolimp-infra`.
- Respostas: diagnóstico → solução → "Resumo para o gestor" (3-5 linhas). Ao concluir: `finalizar-projeto-tecnolimp` (Registro Semanal).

## Pendências conhecidas
- Portal em HTTP sem TLS (risco LGPD) e ~23 s por requisição — fora do escopo, registrado.
- Conector do Senior: tratar como **um relatório por vez por sessão**. No portal, pedidos de holerite (e do nome) passam por uma fila (`filaHolerite`); em paralelo, os meses seguintes falhavam e apareciam como "Em breve".
- Colaborador sem cálculo no mês (ex.: admitido depois; layout quebra em "Antes Imprimir" do Detalhe_Colaborador porque não há cargo na data): bloco 5b da pré-seleção confere a `R046VER` e faz `Mensagem(Erro, "SEMHOLERITE")`; o portal mostra "Sem holerite" (texto: "Aqui aparecem os holerites dos seus 3 últimos meses de trabalho"). Validar no piloto que a marca chega na resposta HTML.
- Produção hoje mostra set/ago/jul **fixos** (manutenção mensal manual, sem regra de pagamento): a virada libera toda folha desses 3 meses.
- Política de aviso prévio difere entre sites (79x/89x não bloqueiam).
- Empresa 9 sem cálculos na R044CAL.

## Próximo passo
HML validado ponta a ponta em 14/10 (painel → fila → integrador com `TEC_LIBHOL` → `USU_TLIBHOL`, agendar e bloquear). Virada das 6 empresas feita.
Produção: seguir `docs/roteiro-producao.md` (migration na VM → integrador PROD → painel no IIS → serviço → pré-seleção de Pontual/Tecnolimp/Deltalimp/DRA → teste final).
Ajustes 15/10 (pedido do Ygor): **sem data automática** — não existe regra D-1/"no padrão" (removida do painel, SQL e manual; `agendar_padrao` segue aceito no banco/integrador só por compatibilidade, sem botão); tooltips (`data-tip`, inclusive "Fora do painel" e "Sem folha"); "Cancelar pedido" na caixa de andamento (migration `008`, `lh_cancelar`, só pedido pendente); "↩ Reverter liberação" na gaveta e no Histórico (= bloquear com motivo); portal com selo "📄 Ver holerite" no mês liberado.
**Encerramento:** a documentação final (PDF) precisa citar o **manual do SQL de contingência** (`docs/manual-sql-contingencia.md`) e o cancelar/reverter do painel.
Sync **sem ciclo fixo** (decisão 6): worker sob demanda, só quando a TI clica no painel.
