-- =====================================================================
-- Piloto em producao: modelos FPFF491/492/493 (empresas 4 e 7)
-- Rodar no ORACLE (Sapiens), um bloco por vez, NO MESMO DIA em que colar
-- as pre-selecoes novas. Sem esta virada, os holerites das empresas 4 e 7
-- somem do portal para todos assim que o bloco 6 entrar.
-- Hoje os modelos mostram set/ago/jul FIXOS (sem regra de pagamento), entao
-- a virada libera tudo que tem folha nesses 3 meses, a partir de hoje no maximo.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ANTES: o que esta visivel hoje (folha mensal dos 3 meses do portal)
-- ---------------------------------------------------------------------
SELECT NumEmp, PerRef, MAX(CodCal) CodCal, MAX(DatPag) DatPag
  FROM R044CAL
 WHERE TipCal = 11 AND NumEmp IN (4, 7)
   AND PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND PerRef <  TRUNC(SYSDATE,'MM')
 GROUP BY NumEmp, PerRef
 ORDER BY NumEmp, PerRef;

-- ---------------------------------------------------------------------
-- 2. VIRADA: registra como liberado (nao mexe em linha que ja exista)
-- ---------------------------------------------------------------------
INSERT INTO USU_TLIBHOL (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
SELECT c.NumEmp, c.PerRef, LEAST(TRUNC(MAX(c.DatPag)) - 1, TRUNC(SYSDATE)), 1, 'VIRADA', TRUNC(SYSDATE),
       'Virada: ja visivel no portal'
  FROM R044CAL c
 WHERE c.TipCal = 11 AND c.NumEmp IN (4, 7)
   AND c.PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND c.PerRef <  TRUNC(SYSDATE,'MM')
   AND NOT EXISTS (SELECT 1 FROM USU_TLIBHOL l
                    WHERE l.USU_NumEmp = c.NumEmp AND l.USU_PerRef = c.PerRef)
 GROUP BY c.NumEmp, c.PerRef;
COMMIT;

-- ---------------------------------------------------------------------
-- 3. CONFERIR: uma linha por empresa + mes do bloco 1, todas SitLib 1 e DatIni <= hoje
-- ---------------------------------------------------------------------
SELECT * FROM USU_TLIBHOL WHERE USU_NumEmp IN (4, 7) ORDER BY USU_NumEmp, USU_PerRef;

-- ---------------------------------------------------------------------
-- 4. (OPCIONAL) Ver o "Em breve" num mes real: bloqueia julho da empresa 7.
--    Afeta TODOS da empresa 7 enquanto estiver bloqueado: fazer rapido e desfazer no 5.
-- ---------------------------------------------------------------------
UPDATE USU_TLIBHOL SET USU_SitLib = 0, USU_UsuLib = 'TESTE', USU_DatGra = TRUNC(SYSDATE), USU_ObsLib = 'Teste do portal'
 WHERE USU_NumEmp = 7 AND USU_PerRef = ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3);
COMMIT;

-- 5. Desfazer o teste do bloco 4
UPDATE USU_TLIBHOL SET USU_SitLib = 1, USU_UsuLib = 'VIRADA', USU_ObsLib = 'Virada: ja visivel no portal'
 WHERE USU_NumEmp = 7 AND USU_PerRef = ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3);
COMMIT;

-- VOLTAR ATRAS (se algo der errado): colar de novo nos 3 modelos a pre-selecao
-- original (originais/FPFF491.OPE.txt, 492, 493). A USU_TLIBHOL pode ficar como esta.
