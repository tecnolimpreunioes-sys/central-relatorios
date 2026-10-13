-- =====================================================================
-- Teste da Fase 1 - bloco 6 no FPFF996 (Juliana 36725E, empresa 3)
-- Rodar no SQL Developer, um bloco por vez, e emitir o FPFF996 entre eles.
-- &comp = competencia que o bloco 5 do FPFF996 calcula (ago/2026 se nHolAtras = 2)
-- Nao mexe nos 15 modelos de producao: so o 996 le a USU_TLIBHOL ate a virada.
-- =====================================================================

-- ---------------------------------------------------------------------
-- E. ESTRUTURA: conferir a tabela criada pelo Sapiens
-- ---------------------------------------------------------------------
-- Esperado: USU_NUMEMP NUMBER, USU_PERREF DATE, USU_DATINI DATE, USU_SITLIB NUMBER,
--           USU_USULIB VARCHAR2(30), USU_DATGRA DATE, USU_OBSLIB VARCHAR2(60)
SELECT column_name, data_type, data_length, data_precision, nullable
  FROM all_tab_columns
 WHERE table_name = 'USU_TLIBHOL'
 ORDER BY column_id;

-- Esperado: USU_NUMEMP e USU_PERREF (chave primaria)
SELECT cc.column_name
  FROM all_constraints c
  JOIN all_cons_columns cc ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name
 WHERE c.table_name = 'USU_TLIBHOL' AND c.constraint_type = 'P'
 ORDER BY cc.position;

-- Folha da competencia de teste existe? (DatPag usada como referencia)
SELECT NumEmp, CodCal, PerRef, DatPag
  FROM R044CAL
 WHERE NumEmp = 3 AND TipCal = 11 AND PerRef = TO_DATE('&&comp','DD/MM/YYYY')
 ORDER BY CodCal DESC;

-- ---------------------------------------------------------------------
-- T1. SEM LINHA -> esperado: NAO emite
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS linhas FROM USU_TLIBHOL
 WHERE USU_NumEmp = 3 AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY');
-- deve ser 0 -> emitir FPFF996

-- ---------------------------------------------------------------------
-- T2. AGENDADO PARA AMANHA -> esperado: NAO emite
-- ---------------------------------------------------------------------
INSERT INTO USU_TLIBHOL (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
VALUES (3, TO_DATE('&&comp','DD/MM/YYYY'), TRUNC(SYSDATE) + 1, 1, 'TESTE', TRUNC(SYSDATE), 'Teste Fase 1 - T2');
COMMIT;

-- ---------------------------------------------------------------------
-- T3. LIBERADO HOJE -> esperado: EMITE (liquido 463,99)
-- ---------------------------------------------------------------------
UPDATE USU_TLIBHOL SET USU_DatIni = TRUNC(SYSDATE), USU_ObsLib = 'Teste Fase 1 - T3'
 WHERE USU_NumEmp = 3 AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY');
COMMIT;

-- ---------------------------------------------------------------------
-- T4. BLOQUEADO -> esperado: NAO emite
-- ---------------------------------------------------------------------
UPDATE USU_TLIBHOL SET USU_SitLib = 0, USU_ObsLib = 'Teste Fase 1 - T4'
 WHERE USU_NumEmp = 3 AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY');
COMMIT;

-- ---------------------------------------------------------------------
-- T5. LIMPEZA (a virada grava as linhas definitivas depois)
-- ---------------------------------------------------------------------
DELETE FROM USU_TLIBHOL
 WHERE USU_NumEmp = 3 AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY') AND USU_UsuLib = 'TESTE';
COMMIT;
UNDEFINE comp
