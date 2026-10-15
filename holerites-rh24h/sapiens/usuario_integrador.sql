-- =====================================================================
-- Usuário Oracle do integrador da Liberação de Holerites (decisão 1 do plano)
-- Rodar como DBA. Escreve SÓ na USU_TLIBHOL (sem DELETE: bloquear = SitLib 0)
-- e lê a R044CAL. Trocar &dono pelo dono das tabelas do Sapiens e definir
-- uma senha forte (guardar no credenciais.bat da TECNOLIMP12, nunca no Git).
-- Registrar esta exceção à regra "escrita no Senior só por web service".
-- =====================================================================
CREATE USER TEC_LIBHOL IDENTIFIED BY "&senha";
GRANT CREATE SESSION TO TEC_LIBHOL;
GRANT SELECT, INSERT, UPDATE ON &dono..USU_TLIBHOL TO TEC_LIBHOL;
GRANT SELECT ON &dono..R044CAL TO TEC_LIBHOL;

-- Conferir (deve listar só SELECT/INSERT/UPDATE na USU_TLIBHOL e SELECT na R044CAL)
SELECT table_name, privilege FROM dba_tab_privs WHERE grantee = 'TEC_LIBHOL' ORDER BY 1, 2;
-- No credenciais.bat: set LH_ORACLE_USER=TEC_LIBHOL / LH_ORACLE_PASSWORD=... / LH_ESQUEMA=<dono>
