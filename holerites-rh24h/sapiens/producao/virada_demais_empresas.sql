-- =====================================================================
-- Virada das demais empresas: Tecnolimp (1), Pontual (3), DRA (5), Deltalimp (6)
-- (ServiPlus 4 e Servinews 7 ja viraram no piloto: virada_empresas_4_7.sql)
-- Rodar no ORACLE (Sapiens), um bloco por vez, NO MESMO DIA em que colar as
-- pre-selecoes novas nos modelos dessas empresas (591-593, 691-693, 791-793, 891-893).
-- Libera tudo que tem folha nos 3 meses do portal, a partir de hoje no maximo.
-- =====================================================================

-- 1. ANTES: folhas dos 3 meses do portal
SELECT NumEmp, PerRef, MAX(CodCal) CodCal, MAX(DatPag) DatPag
  FROM R044CAL
 WHERE TipCal = 11 AND NumEmp IN (1, 3, 5, 6)
   AND PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND PerRef <  TRUNC(SYSDATE,'MM')
 GROUP BY NumEmp, PerRef
 ORDER BY NumEmp, PerRef;

-- 2. VIRADA (nao mexe em linha que ja exista)
INSERT INTO USU_TLIBHOL (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
SELECT c.NumEmp, c.PerRef, LEAST(TRUNC(MAX(c.DatPag)) - 1, TRUNC(SYSDATE)), 1, 'VIRADA', TRUNC(SYSDATE),
       'Virada: ja visivel no portal'
  FROM R044CAL c
 WHERE c.TipCal = 11 AND c.NumEmp IN (1, 3, 5, 6)
   AND c.PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND c.PerRef <  TRUNC(SYSDATE,'MM')
   AND NOT EXISTS (SELECT 1 FROM USU_TLIBHOL l
                    WHERE l.USU_NumEmp = c.NumEmp AND l.USU_PerRef = c.PerRef)
 GROUP BY c.NumEmp, c.PerRef;
COMMIT;

-- 3. CONFERIR: uma linha por empresa + mes do bloco 1, todas SitLib 1. E nenhuma sobra de teste:
SELECT * FROM USU_TLIBHOL ORDER BY USU_NumEmp, USU_PerRef;
SELECT * FROM USU_TLIBHOL WHERE USU_UsuLib = 'TESTE';   -- esperado: nenhuma linha

-- VOLTAR ATRAS: colar de novo a pre-selecao original do modelo (originais/FPFFxxx.OPE.txt).
