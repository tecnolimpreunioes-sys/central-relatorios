# Manual — SQL de contingência da Liberação de Holerites

Arquivo: `holerites-rh24h/sapiens/sql_contingencia.sql` · Público: TI · Atualizado em 15/10/2026

## Para que serve
Liberar, agendar ou bloquear um holerite do portal RH 24h **direto no Sapiens**, sem o painel da Central. É o plano B; no dia a dia use sempre o painel.

Use só quando:
- o painel (`central.apps.tecnolimp.local/relatorios/liberacao-holerites/`) ou o Supabase estiver fora do ar, **ou**
- o integrador da TECNOLIMP12 não responder (aviso amarelo "O integrador com o Sapiens não respondeu") e o RH precisar da mudança agora.

## O que ele faz
O portal só mostra o holerite de um mês quando existe uma linha liberada na tabela `VETORH.USU_TLIBHOL` (pré-seleção dos modelos FPFF491…893). O SQL mexe só nessa tabela:

| Bloco | O que faz | Efeito no portal |
|---|---|---|
| 0. Consultar | Lista as folhas dos meses do portal e a situação de cada empresa | nenhum (só leitura) |
| 1. Liberar / agendar | Cria ou atualiza a linha com `USU_SitLib = 1` e a data inicial | aparece a partir da data (hoje = na hora) |
| 2. Bloquear / reverter | Muda a linha para `USU_SitLib = 0` | volta a "🔒 Em breve" |
| 3. Gravar | `COMMIT` | confirma a mudança |

Nunca apaga linha e não mexe em nenhuma outra tabela do Senior. Cada mudança grava quem fez (`USU_UsuLib`), quando (`USU_DatGra`) e o motivo (`USU_ObsLib`).

## Como usar (passo a passo)
1. **Onde:** DBeaver conectado ao **Sapiens (Oracle)**. Nunca no SQL Editor do Supabase.
2. Abra `sql_contingencia.sql` e rode o **bloco 0** (selecione o bloco → Ctrl+Enter). Localize a empresa e a competência.
3. No bloco 1 (liberar/agendar) ou no bloco 2 (bloquear), troque **só** as linhas marcadas `<-- TROCAR`:

   | Campo | Exemplo | Observação |
   |---|---|---|
   | Empresa | `3` | Tecnolimp 1 · Pontual 3 · ServiPlus 4 · DRA 5 · Deltalimp 6 · Servinews 7 |
   | Competência | `DATE '2026-09-01'` | sempre dia 01 do mês da folha |
   | A partir de (bloco 1) | `TRUNC(SYSDATE)` = hoje · `DATE '2026-11-04'` = data marcada | sempre uma data escolhida pela TI |
   | Usuário | `'ygor.adm'` | seu usuário de rede |
   | Motivo | `'Contingencia: RH (Dayane) pediu'` | até 60 caracteres |

4. Rode o bloco escolhido. Esperado: **1 linha** afetada.
   - Bloco 2 com 0 linhas = já estava bloqueado; nada a fazer.
5. Rode o **bloco 0** de novo e confira a coluna `SITUACAO`.
6. Rode o **bloco 3 (`COMMIT`)**. Para desistir antes disso: `ROLLBACK;`.
   - Se o DBeaver estiver em **Auto-Commit** (ícone na barra), a mudança já foi gravada no passo 4. Para desfazer, rode o bloco oposto (1 ↔ 2).
7. Quando o painel voltar: **"↻ Atualizar do Sapiens"**. A mudança entra no Histórico como **"fora do painel"** com o usuário informado.

## Exemplos prontos
- **Liberar setembro da Pontual agora:** bloco 1 com `3`, `DATE '2026-09-01'`, `TRUNC(SYSDATE)`.
- **Agendar outubro da Tecnolimp para 04/11:** bloco 1 com `1`, `DATE '2026-10-01'`, `DATE '2026-11-04'`.
- **Reverter setembro da DRA (foi liberado por engano):** bloco 2 com `5`, `DATE '2026-09-01'`.

## Cuidados
- Rode **um bloco por vez**; nunca o arquivo inteiro.
- Confira no bloco 0 se a competência tem folha calculada; sem folha não há holerite para liberar.
- O colaborador vê a mudança na próxima vez que abrir o holerite. Ninguém vê data de liberação, só "🔒 Em breve".
- Não use para a virada nem para trocar a pré-seleção dos modelos: isso fica em `sapiens/producao/`.
