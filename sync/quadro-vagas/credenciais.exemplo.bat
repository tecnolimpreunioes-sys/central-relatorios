@echo off
rem Copiar para credenciais.bat (NUNCA versionar nem incluir no zip) e preencher.
rem Python do usuário que roda a tarefa (o caminho muda por usuário do Windows).
set PYEXE=C:\Users\USUARIO\AppData\Local\Programs\Python\Python312\python.exe

rem Oracle/Sapiens (somente leitura)
set ORACLE_USER=
set ORACLE_PASSWORD=
set ORACLE_DSN=localhost:1521/SAPIENS
rem Só para Oracle anterior a 12.1 (modo thick): pasta do Instant Client
rem set ORACLE_CLIENT_DIR=C:\oracle\instantclient_19_20

rem Supabase de produção (service_role — só aqui, nunca no site)
set SUPABASE_URL=http://supabase.tecnolimp.local:8000
set SUPABASE_SERVICE_KEY=
set NO_PROXY=supabase.tecnolimp.local,localhost,127.0.0.1

rem Opcional: título do cargo (TitRed = igual ao FPRF307; TitCar = título completo)
rem set QV_CAMPO_TITULO_CARGO=TitRed
