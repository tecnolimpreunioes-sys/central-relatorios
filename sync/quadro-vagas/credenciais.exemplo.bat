@echo off
REM credenciais.bat do worker Quadro de Vagas - NUNCA versionar nem incluir no zip.
REM Oracle: reaproveita a FONTE UNICA de credenciais do sync (ORACLE_USER, ORACLE_PASSWORD,
REM ORACLE_HOST, ORACLE_PORT, ORACLE_SID). Ajuste o caminho para a pasta do sync:
call "C:\CAMINHO\DO\SYNC\credenciais.bat"

REM Python do usuario que roda a tarefa (o caminho muda por usuario do Windows).
REM Se a fonte unica ja define PYEXE, apague a linha abaixo.
set PYEXE=C:\Users\USUARIO\AppData\Local\Programs\Python\Python312\python.exe

REM Oracle anterior a 12.1 (modo thick): pasta do Instant Client
REM set ORACLE_CLIENT_DIR=C:\oracle\instantclient_19_20

REM --- Supabase de producao (service_role: so aqui, nunca no site) ---
REM Se a fonte unica ja define SUPABASE_URL e a chave, apague as linhas abaixo.
set SUPABASE_URL=http://supabase.tecnolimp.local:8000
set SUPABASE_SERVICE_KEY=
set NO_PROXY=supabase.tecnolimp.local,localhost,127.0.0.1

REM Opcional: titulo do cargo (TitRed = igual ao FPRF307; TitCar = titulo completo)
REM set QV_CAMPO_TITULO_CARGO=TitRed
