@echo off
REM Integrador da Liberacao de Holerites: ouve a fila da Central e so toca o
REM Oracle quando a TI clica no painel. Reinicia sozinho se cair.
cd /d "%~dp0"
if not exist credenciais.bat (echo Falta credenciais.bat - copie de credenciais.exemplo.bat & exit /b 1)
call credenciais.bat
:loop
"%PYEXE%" worker_liberacao_holerites.py
echo [%date% %time%] Integrador parou; reiniciando em 15s...
timeout /t 15 /nobreak >nul
goto loop
