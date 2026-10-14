@echo off
REM credenciais.bat do integrador Liberacao de Holerites - NUNCA versionar nem incluir no zip.
REM Oracle: reaproveita a FONTE UNICA de credenciais do sync (ORACLE_USER, ORACLE_PASSWORD,
REM ORACLE_HOST, ORACLE_PORT, ORACLE_SID). Aponte para o credenciais.bat (NAO o run_sync.bat).
REM Prefira caminho relativo a esta pasta (%~dp0): o cmd le .bat em OEM e quebra acentos
REM como "Automacoes" com cedilha. Ex.: esta pasta e "08 - Liberacao holerite", irma de "03 - Relacao_Eventos":
call "%~dp0..\03 - Relacao_Eventos\credenciais.bat"

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

REM --- Oracle: usuario DEDICADO (decisao 1 do plano) ---
REM Grants: SELECT, INSERT, UPDATE so na USU_TLIBHOL + SELECT na R044CAL. Sem DELETE.
REM Sem estas linhas o integrador usa o usuario do sync (aviso no log).
set LH_ORACLE_USER=
REM Entre aspas: senha com & ^ % quebra o set sem elas
set "LH_ORACLE_PASSWORD="
REM Dono das tabelas do Sapiens (obrigatorio com o usuario dedicado)
set "LH_ESQUEMA=VETORH"
