# Plano — Liberação manual de holerites (RH 24h)

Status: **decisões aprovadas** (13/10/2026). `USU_TLIBHOL` criada e **bloco 6 validado no FPFF996** (14/10, usuário 628S7, T1–T5 ok).

## Requisito (definido pelo Ygor)
- Todo holerite **bloqueado por padrão**; a **TI** libera (a pedido do RH). Não depender do RH executar nada.
- Portal continua igual: combo com os 3 meses mais recentes; mês não liberado (bloqueado ou agendado) mostra só "🔒 Em breve", sem data.
- Precisa suportar **agendamento** (RH avisa antes: "solta dia 04").
- Ferramenta da TI: painel na intranet (Central de Relatórios, área T.I.).

## Alternativas descartadas (e por quê)
- v2 "RH roda relatório FPLIBHOL para liberar": cria dependência mensal do RH.
- v3 "automático D-1 + bloqueio por exceção": Ygor quer o inverso (padrão bloqueado).
- Trava só no site/JS: inseguro — o conector entrega o PDF se chamado direto pela URL. A trava tem que ser na pré-seleção (Oracle).
- Sync em ciclo fixo (Agendador a cada 5 min): descartado na decisão 6 — roda só quando alguém clica.

## Arquitetura
```
Central de Relatórios (intranet)          TECNOLIMP12 (worker Python, parado)      Sapiens/Oracle
TI clica Liberar/Agendar/Bloquear/  ──▶  acorda com o pedido (Realtime)      ──▶  USU_TLIBHOL
Atualizar → grava "pedido" no Supabase    1) grava decisão na USU_TLIBHOL           │
                                    ◀──  2) relê R044CAL + USU_TLIBHOL → Supabase   │
painel mostra "aplicado" ou "erro"        3) marca o pedido aplicado/erro            ▼
                                              Portal RH 24h ◀── pré-seleção dos 15 modelos (bloco 6)
```
- **Agendamento não precisa de processo rodando**: a data "a partir de" fica gravada na `USU_TLIBHOL` e a própria pré-seleção compara com a data do dia.
- O worker só toca o Oracle quando chega pedido. Ele consulta a fila `lh_pedidos` a cada poucos segundos (consulta barata ao Supabase, mesmo padrão do Quadro de Vagas). Se ele estiver fora, o pedido fica "pendente" e o painel avisa após 1 min → TI usa o SQL de contingência.

## Peças
1. **`USU_TLIBHOL`** (tabela de usuário criada pelo Sapiens, como a USU_TFALCOB) — chave empresa + competência.
   Definição: `sapiens/USU_TLIBHOL.md`.
   `USU_NumEmp` N4 PK, `USU_PerRef` Data PK, `USU_DatIni` Data (liberar a partir de — **sempre preenchida**),
   `USU_SitLib` N1 (1 liberado / 0 bloqueado), `USU_UsuLib` A30, `USU_DatGra` Data, `USU_ObsLib` A60.
   A regra "vazio = DatPag − 1" (decisão 3) é resolvida **na gravação** (painel/worker/SQL), não na pré-seleção:
   mantém o LSP com uma comparação só e sem ambiguidade de data vazia (31/12/1900 × NULL).
2. **Bloco 6 da pré-seleção** (igual nos 15): `sapiens/preselecao_fase2_liberacao.txt`. Bloco 5 deixa de filtrar DatPag
   e pega o CodCal mais recente da competência (TipCal 11); bloco 6 só emite se existir linha com
   `USU_SitLib = 1 AND USU_DatIni <= hoje`. Cursor simples, campos sem prefixo de tabela.
3. **Supabase** — `migrations/007_liberacao_holerites.sql` (schema `central`, como os demais relatórios da Central; testada em Postgres local com
   `migrations/testes/`): `lh_folhas` (espelho R044CAL), `lh_liberacoes` (espelho USU_TLIBHOL), `lh_pedidos` (fila de cliques), `lh_log` (auditoria).
   Navegador só lê (RLS por `lh_pode()` = login + slug `liberacao-holerites`, nunca acesso livre) e escreve só por `lh_solicitar` (valida tudo).
   Worker (service_role): `lh_proximo` → grava no Oracle → `lh_concluir` (espelho + log "painel") → `lh_espelhar` (diferenças = "fora do painel") → `lh_manutencao`.
4. **Worker Python** na TECNOLIMP12 (serviço, ocioso até chegar pedido): aplica na `USU_TLIBHOL` (idempotente, binds),
   relê R044CAL e USU_TLIBHOL para o Supabase. Diferença entre USU_TLIBHOL e o espelho = alteração feita por SQL de
   contingência → registra no log como "fora do painel". Usuário Oracle próprio com grant só na `USU_TLIBHOL`; `service_role` só no worker.
5. **Painel** `relatorios/liberacao-holerites/` na Central, **só TI** (decisão 5): grade empresa × 3 competências
   (🔒 bloqueado / 🕒 agendado / ✅ liberado / ⏳ pedido pendente), botões Liberar / Agendar / Bloquear / Atualizar, histórico. Permissão por slug + RLS.
6. **SQL de contingência** (TI, Oracle): `sapiens/sql_contingencia.sql` — consultar, liberar agora, agendar, bloquear, virada.
7. **index.html**: mensagem "🔒 Em breve" (colaborador nunca vê a data de liberação).

## Fases
| Fase | Entrega | Valor sozinha |
|---|---|---|
| 1 | Tabela + bloco 6 no FPFF996 (teste Juliana) + virada + 15 modelos | Sim — TI libera por SQL |
| 2 | Schema Supabase + RLS + permissão Central | — |
| 3 | Worker Python sob demanda (serviço na TECNOLIMP12) | — |
| 4 | Painel na Central | Sim — rotina por clique |
| 5 | HML → PROD, cadastro na Central, teste com usuário não-admin | — |
| 6 | Documentação + Registro Semanal | — |

### Roteiro de teste da Fase 1 (FPFF996, Juliana 36725E, emp. 3, ago/2026)
| # | Estado na USU_TLIBHOL | Esperado |
|---|---|---|
| 1 | sem linha | não emite |
| 2 | SitLib 1, DatIni = amanhã | não emite |
| 3 | SitLib 1, DatIni = hoje | emite, líquido 463,99 |
| 4 | SitLib 0 | não emite |
| 5 | apagar a linha de teste (ou deixar conforme virada) | — |

**Virada obrigatória:** antes de publicar o bloco 6 nos 15 modelos, rodar o bloco VIRADA do `sql_contingencia.sql`
(registra como liberadas as competências já visíveis no portal), senão somem para todos.

## Decisões (aprovadas 13/10/2026)
1. Escrita no Oracle: **A** — exceção para gravar **só** na `USU_TLIBHOL` (usuário Oracle dedicado, grant só nessa tabela). Registrar a exceção formalmente.
2. Liberação por empresa + mês, todos os colaboradores juntos.
3. "A partir de" vazio = 1 dia antes do pagamento (resolvido na gravação).
4. Recálculo após liberado continua visível com o cálculo mais recente.
5. Painel acessível **só pela TI**.
6. **Sem ciclo fixo**: o sync roda só quando alguém clica no painel (worker sob demanda). Urgência / worker fora: SQL de contingência.

## Resumo para o gestor
Holerite passa a ficar bloqueado por padrão e só aparece no portal quando a TI libera, a pedido do RH, por uma tela na intranet (Central de Relatórios, acesso só da TI) — com agendamento, bloqueio imediato e histórico de quem fez. A trava fica no Sapiens, então não há como contornar pelo site. Nada roda em segundo plano: a integração só trabalha quando a TI clica. A Fase 1 já entrega o controle funcionando por SQL; a tela vem em seguida.
