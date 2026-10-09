@echo off
REM Worker do Quadro de Vagas: fica ouvindo a fila da Central e so consulta o
REM Oracle quando alguem clica em "Gerar". Reinicia sozinho se cair.
cd /d "%~dp0"
if not exist credenciais.bat (echo Falta credenciais.bat - copie de credenciais.exemplo.bat & exit /b 1)
call credenciais.bat
:loop
"%PYEXE%" worker_quadro_vagas.py
echo [%date% %time%] Worker parou; reiniciando em 15s...
timeout /t 15 /nobreak >nul
goto loop
