# Worker — Quadro de Vagas (FPRF307)

Roda na **TECNOLIMP12**. Ouve a fila `central.qv_solicitacoes` no Supabase e só consulta o Oracle quando alguém clica em **Gerar** na Central (`relatorios/quadro-vagas/`). Nenhuma carga agendada.

## Instalação
1. Copiar a pasta para a TECNOLIMP12 (ex.: `C:\Scripts\quadro-vagas`).
2. `"%PYEXE%" -m pip install -r requirements.txt`
3. Copiar `credenciais.exemplo.bat` → `credenciais.bat`: ele chama a **fonte única** de credenciais do sync (Oracle por `ORACLE_HOST/PORT/SID`) e acrescenta só o que faltar (`PYEXE`, `SUPABASE_*`). Fica só na máquina.
4. Validar o Oracle antes de ligar o serviço:
   - `call credenciais.bat & "%PYEXE%" worker_quadro_vagas.py --diagnostico` (colunas de R016HIE, R016ORN, R024CAR…)
   - `call credenciais.bat & "%PYEXE%" worker_quadro_vagas.py --teste --empresa 3 --local 3.111==` e conferir com o FPRF307.
5. Como administrador: `powershell -ExecutionPolicy Bypass -File .\instalar_tarefa.ps1`.

## Operação
- Log: `logs\worker_quadro_vagas.log` (rotativo).
- Tela mostra "O serviço de geração não respondeu" → tarefa parada: Agendador › *Tecnolimp - Quadro de Vagas (worker)* › Executar.
- Atualização: substituir só os `.py`/`.bat`/`.ps1` (o zip nunca leva `credenciais.bat`) e reiniciar a tarefa.
