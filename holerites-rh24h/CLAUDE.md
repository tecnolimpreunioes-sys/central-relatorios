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
| Portal `index.html` (meses automáticos + 5 correções) | **Pronto**: `portal/index.html`, aguardando publicação |
| 2. Liberação manual (padrão bloqueado, TI libera) | **Decisões aprovadas 13/10** — `docs/plano-liberacao.md`. Código da Fase 1 pronto e **não testado**: `sapiens/preselecao_fase2_liberacao.txt` (bloco 6), `sapiens/USU_TLIBHOL.md`, `sapiens/sql_contingencia.sql`, roteiro executável `sapiens/teste_fase1.sql`. Teste da Fase 2 no FPFF996 com o usuário **628S7** (empresa 7 ServiPlus, parâmetros do site 49x: `aHolSite "4,7"`, ago/2026); `USU_TLIBHOL` criada e conferida em 14/10. Protótipo do painel: `prototipos/liberacao-holerites.html` |

## Parâmetros por modelo (pré-seleção genérica, só 3 linhas mudam)
| Site | `aHolSite` | `nHolAviso` |
|---|---|---|
| 49x | "4,7" | 1 |
| 59x | "3" | 1 |
| 69x | "1,9" | 1 |
| 79x | "6" | 0 |
| 89x | "5" | 0 |
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
- Política de aviso prévio difere entre sites (79x/89x não bloqueiam).
- Empresa 9 sem cálculos na R044CAL.

## Próximo passo
Personalização da `USU_TLIBHOL` confirmada no Sapiens → `teste_fase1.sql` + bloco 6 no FPFF996 (Juliana) → usuário Oracle dedicado → integrador na TECNOLIMP12 (`--diagnostico`, `--leitura`) → Fase 4 (painel) → virada → 15 modelos.
Sync **sem ciclo fixo** (decisão 6): worker sob demanda, só quando a TI clica no painel.
