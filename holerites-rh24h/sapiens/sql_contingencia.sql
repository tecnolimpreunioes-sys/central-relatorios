-- =====================================================================
-- Liberacao de holerites RH 24h - SQL de contingencia da TI (Oracle)
-- Uso: quando o painel/worker estiver fora ou for urgente.
-- Depois de rodar, clicar "Atualizar do Sapiens" no painel: a mudanca
-- entra no historico como "fora do painel".
-- Rodar no SQL Developer (variaveis &). Sempre COMMIT ao final.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. CONSULTAR: situacao das ultimas 3 competencias por empresa
-- ---------------------------------------------------------------------
SELECT c.NumEmp, c.PerRef, MAX(c.CodCal) CodCal, MAX(c.DatPag) DatPag,
       l.USU_SitLib, l.USU_DatIni, l.USU_UsuLib, l.USU_DatGra, l.USU_ObsLib,
       CASE WHEN l.USU_NumEmp IS NULL OR l.USU_SitLib = 0 THEN 'BLOQUEADO'
            WHEN l.USU_DatIni > TRUNC(SYSDATE)              THEN 'AGENDADO'
            ELSE 'LIBERADO' END Situacao
  FROM R044CAL c
  LEFT JOIN USU_TLIBHOL l ON l.USU_NumEmp = c.NumEmp AND l.USU_PerRef = c.PerRef
 WHERE c.TipCal = 11
   AND c.PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND c.PerRef <  TRUNC(SYSDATE,'MM')
 GROUP BY c.NumEmp, c.PerRef, l.USU_NumEmp, l.USU_SitLib, l.USU_DatIni, l.USU_UsuLib, l.USU_DatGra, l.USU_ObsLib
 ORDER BY c.PerRef DESC, c.NumEmp;

-- ---------------------------------------------------------------------
-- 1. LIBERAR AGORA / AGENDAR
--    &emp  = empresa             ex.: 3
--    &comp = competencia         ex.: 01/09/2026
--    &ini  = a partir de         ex.: 04/10/2026  (vazio = DatPag - 1)
--    &usu  = usuario de rede     ex.: ygor.adm
--    &obs  = quem pediu / motivo (ate 60)
-- ---------------------------------------------------------------------
MERGE INTO USU_TLIBHOL l
USING (SELECT &emp NumEmp,
              TO_DATE('&comp','DD/MM/YYYY') PerRef,
              NVL(TO_DATE('&ini','DD/MM/YYYY'),
                  (SELECT MAX(DatPag) - 1 FROM R044CAL
                    WHERE NumEmp = &emp AND TipCal = 11
                      AND PerRef = TO_DATE('&comp','DD/MM/YYYY'))) DatIni
         FROM dual) s
   ON (l.USU_NumEmp = s.NumEmp AND l.USU_PerRef = s.PerRef)
 WHEN MATCHED THEN UPDATE SET
      l.USU_SitLib = 1, l.USU_DatIni = TRUNC(s.DatIni),
      l.USU_UsuLib = '&usu', l.USU_DatGra = TRUNC(SYSDATE), l.USU_ObsLib = SUBSTR('&obs',1,60)
 WHEN NOT MATCHED THEN INSERT
      (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
      VALUES (s.NumEmp, s.PerRef, TRUNC(s.DatIni), 1, '&usu', TRUNC(SYSDATE), SUBSTR('&obs',1,60));
-- Conferir: se DatIni ficou NULL a competencia nao tem folha calculada -> ROLLBACK.
-- Liberar agora = informar &ini com a data de hoje.

-- ---------------------------------------------------------------------
-- 2. BLOQUEAR (some do portal na proxima consulta)
-- ---------------------------------------------------------------------
UPDATE USU_TLIBHOL
   SET USU_SitLib = 0, USU_UsuLib = '&usu', USU_DatGra = TRUNC(SYSDATE), USU_ObsLib = SUBSTR('&obs',1,60)
 WHERE USU_NumEmp = &emp
   AND USU_PerRef = TO_DATE('&comp','DD/MM/YYYY');
-- 0 linhas = ja estava bloqueado (sem registro).

COMMIT;

-- =====================================================================
-- VIRADA (uma vez, ANTES de publicar o bloco 6 nos 15 modelos)
-- Registra como liberado tudo que hoje ja aparece no portal.
-- Os modelos de producao mostram os 3 meses FIXOS (set/ago/jul), sem regra de
-- pagamento: libera toda folha mensal da janela, a partir de hoje no maximo.
-- Piloto so com as empresas 4 e 7: producao/virada_empresas_4_7.sql
-- =====================================================================
-- V1. Conferencia: competencias com mais de um calculo mensal
--     (a regra nova usa o CodCal mais recente, sem olhar DatPag)
SELECT NumEmp, PerRef, COUNT(*) Qtd, MIN(DatPag), MAX(DatPag)
  FROM R044CAL
 WHERE TipCal = 11
   AND PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND PerRef <  TRUNC(SYSDATE,'MM')
 GROUP BY NumEmp, PerRef
HAVING COUNT(*) > 1;

-- V2. Registrar
INSERT INTO USU_TLIBHOL (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
SELECT c.NumEmp, c.PerRef, LEAST(TRUNC(MAX(c.DatPag)) - 1, TRUNC(SYSDATE)), 1, 'VIRADA', TRUNC(SYSDATE), 'Virada: ja visivel no portal'
  FROM R044CAL c
 WHERE c.TipCal = 11
   AND c.PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
   AND c.PerRef <  TRUNC(SYSDATE,'MM')
   AND NOT EXISTS (SELECT 1 FROM USU_TLIBHOL l
                    WHERE l.USU_NumEmp = c.NumEmp AND l.USU_PerRef = c.PerRef)
 GROUP BY c.NumEmp, c.PerRef;

-- V3. Conferir com o bloco 0 (todos que estavam visiveis devem aparecer LIBERADO) e COMMIT.
