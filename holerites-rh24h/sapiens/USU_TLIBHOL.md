# USU_TLIBHOL — Liberação de holerites RH 24h

Tabela de usuário criada **pelo Sapiens** (Personalização › Tabelas de usuário), igual à USU_TFALCOB — não criar por DDL direto.
Uma linha por empresa + competência. Sem linha = bloqueado (padrão).

| Campo | Tipo | Chave | Descrição |
|---|---|---|---|
| `USU_NumEmp` | Número 4 | PK | Empresa (R044CAL.NumEmp) |
| `USU_PerRef` | Data | PK | Competência, sempre dia 01 (R044CAL.PerRef) |
| `USU_DatIni` | Data | | Libera a partir de. **Sempre preenchida**, sempre com a data escolhida pela TI (não há data automática) |
| `USU_SitLib` | Número 1 | | 1 = liberado, 0 = bloqueado |
| `USU_UsuLib` | Alfa 30 | | Usuário de rede que fez a última alteração (ou `VIRADA`) |
| `USU_DatGra` | Data | | Data da última alteração |
| `USU_ObsLib` | Alfa 60 | | Quem pediu / motivo |

## Regra lida pela pré-seleção (bloco 6, 15 modelos)
Emite só se existir linha com `USU_SitLib = 1 AND USU_DatIni <= DatSis` para a empresa e a competência do combo.

## Acesso (decisão 1 = A)
- Usuário Oracle dedicado para o worker, com `SELECT, INSERT, UPDATE` **só** nesta tabela (+ `SELECT` na R044CAL). Sem `DELETE`: bloquear = `USU_SitLib = 0`.
- Registrar formalmente a exceção à regra "escrita no Senior só por web service".
- Datas sempre gravadas com `TRUNC` (sem hora), senão `USU_DatIni <= DatSis` falha no próprio dia.
