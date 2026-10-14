-- =====================================================================
-- Teste da Fase 1 - bloco 6 no FPFF996 (usuario de teste 628S7 = cadastro 628, empresa 7 ServiPlus)
-- Rodar no SQL Developer, um bloco por vez, e emitir o FPFF996 entre eles.
-- &emp  = empresa do usuario de teste (7)
-- &cad  = cadastro do usuario de teste (628)
-- &comp = competencia que o bloco 5 do FPFF996 calcula (01/08/2026 se nHolAtras = 2)
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

-- ---------------------------------------------------------------------
-- P. PRE-REQUISITOS do usuario de teste (todos precisam bater, senao o 996 nao emite nem no T3)
-- ---------------------------------------------------------------------
-- Login existe no Senior (bloco 1): esperado 1 linha
SELECT CodUsu, NomUsu FROM R999USU WHERE NomUsu = '&&cad' || 'S7';

-- Folha mensal da competencia (bloco 5): esperado ao menos 1 linha
SELECT NumEmp, CodCal, PerRef, DatPag
  FROM R044CAL
 WHERE NumEmp = &&emp AND TipCal = 11 AND PerRef = TO_DATE('&&comp','DD/MM/YYYY')
 ORDER BY CodCal DESC;

-- Aviso previo (bloco 4, site 49x bloqueia): esperado 0 linhas
SELECT NumEmp, NumCad, DatAvi FROM R042AVI WHERE NumEmp = &&emp AND NumCad = &&cad AND MotCan <> 9;

-- Ativo na empresa (filtro do relatorio): esperado 1 linha com SitAfa <> 7
SELECT NumEmp, NumCad, SitAfa FROM R034FUN WHERE NumEmp = &&emp AND TipCol = 1 AND NumCad = &&cad;

-- ---------------------------------------------------------------------
-- T1. SEM LINHA -> esperado: NAO emite
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS linhas FROM USU_TLIBHOL
 WHERE USU_NumEmp = &&emp AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY');
-- deve ser 0 -> emitir FPFF996

-- ---------------------------------------------------------------------
-- T2. AGENDADO PARA AMANHA -> esperado: NAO emite
-- ---------------------------------------------------------------------
INSERT INTO USU_TLIBHOL (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
VALUES (&&emp, TO_DATE('&&comp','DD/MM/YYYY'), TRUNC(SYSDATE) + 1, 1, 'TESTE', TRUNC(SYSDATE), 'Teste Fase 1 - T2');
COMMIT;

-- ---------------------------------------------------------------------
-- T3. LIBERADO HOJE -> esperado: EMITE o holerite do 628S7 de ago/2026
-- ---------------------------------------------------------------------
UPDATE USU_TLIBHOL SET USU_DatIni = TRUNC(SYSDATE), USU_ObsLib = 'Teste Fase 1 - T3'
 WHERE USU_NumEmp = &&emp AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY');
COMMIT;

-- ---------------------------------------------------------------------
-- T4. BLOQUEADO -> esperado: NAO emite
-- ---------------------------------------------------------------------
UPDATE USU_TLIBHOL SET USU_SitLib = 0, USU_ObsLib = 'Teste Fase 1 - T4'
 WHERE USU_NumEmp = &&emp AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY');
COMMIT;

-- ---------------------------------------------------------------------
-- T5. LIMPEZA (a virada grava as linhas definitivas depois)
-- ---------------------------------------------------------------------
DELETE FROM USU_TLIBHOL
 WHERE USU_NumEmp = &&emp AND USU_PerRef = TO_DATE('&&comp','DD/MM/YYYY') AND USU_UsuLib = 'TESTE';
COMMIT;
UNDEFINE emp
UNDEFINE cad
UNDEFINE comp
