# Integrador — Liberação de Holerites (RH 24h)

Roda na **TECNOLIMP12**. Ouve a fila `central.lh_pedidos` no Supabase e só toca o Oracle quando a T.I. clica no painel da Central (`relatorios/liberacao-holerites/`), e uma vez ao iniciar. Grava **somente** na `USU_TLIBHOL`; lê `R044CAL` e `USU_TLIBHOL`.

| Clique no painel | O que grava na USU_TLIBHOL |
|---|---|
| Liberar agora | `SitLib 1`, `DatIni` = hoje |
| Agendar | `SitLib 1`, `DatIni` = data escolhida |
| Todas no padrão | `SitLib 1`, `DatIni` = pagamento − 1 (por empresa) |
| Bloquear | `SitLib 0` (nunca apaga; sem linha = já bloqueado) |
| Atualizar do Sapiens | nada; só relê |

Depois de cada pedido relê a janela (mês atual até 3 meses atrás). Diferença entre o Sapiens e o painel que não veio de um clique (SQL de contingência) entra no histórico como **fora do painel**.

## Instalação
1. **Usuário Oracle dedicado** (decisão 1 do plano): o DBA roda `sapiens/usuario_integrador.sql` (`SELECT/INSERT/UPDATE` só na `USU_TLIBHOL`, `SELECT` na `R044CAL`, sem `DELETE`).
2. Copiar a pasta para a TECNOLIMP12 (ex.: `C:\Scripts\liberacao-holerites`).
3. `"%PYEXE%" -m pip install -r requirements.txt`
4. `credenciais.exemplo.bat` → `credenciais.bat`: chama a fonte única do sync e acrescenta `LH_ORACLE_USER/PASSWORD` (e `LH_ESQUEMA` se o usuário dedicado não for o dono das tabelas). Fica só na máquina.
5. Validar antes de ligar:
   - `call credenciais.bat & "%PYEXE%" worker_liberacao_holerites.py --diagnostico` → colunas, grants e contagens.
   - `... --leitura` → JSON do que iria para o painel (não grava nada). Conferir folhas e a virada.
   - `... --espelhar` → atualiza o painel uma vez.
6. Como administrador: `powershell -ExecutionPolicy Bypass -File .\instalar_tarefa.ps1`.

## Operação
- Log: `logs\worker_liberacao_holerites.log` (rotativo).
- Painel avisa "integrador não respondeu" (pedido pendente há mais de 1 min) → Agendador › *Tecnolimp - Liberacao de Holerites (integrador)* › Executar. Urgência: `sapiens/sql_contingencia.sql` (manual: `holerites-rh24h/docs/manual-sql-contingencia.md`) e depois "Atualizar do Sapiens".
- Pedido pendente há mais de 1 dia expira (não aplica decisão velha); processando há mais de 10 min vira erro.
- Atualização: substituir só os `.py`/`.bat`/`.ps1` (o zip nunca leva `credenciais.bat`) e reiniciar a tarefa.

## Teste sem Oracle
`testes/teste_integrador.py`: Sapiens falso em memória + funções `lh_*` reais num Postgres local com as migrations (`migrations/testes/`). Cobre liberar, agendar no padrão, bloquear, bloqueio repetido, falha do Oracle (rollback) e contingência.
