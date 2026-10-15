-- =====================================================================
-- Liberacao de holerites RH 24h - SQL de contingencia da TI (Oracle/Sapiens)
-- Manual: holerites-rh24h/docs/manual-sql-contingencia.md
-- Quando: painel da Central ou integrador da TECNOLIMP12 fora do ar e o RH
-- precisa liberar/bloquear AGORA. Fora isso, use sempre o painel.
-- Onde: DBeaver conectado ao SAPIENS (nunca no Supabase).
-- Como: rode UM bloco por vez (selecione o bloco e Ctrl+Enter).
--       Troque so os valores marcados com  <-- TROCAR .
-- Depois: painel > "Atualizar do Sapiens". A mudanca entra no historico
--         como "fora do painel".
-- Nunca apaga linha: so grava/atualiza a VETORH.USU_TLIBHOL.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. CONSULTAR: situacao dos 3 meses do portal + o mes corrente
-- ---------------------------------------------------------------------
SELECT c.NumEmp, c.PerRef, MAX(c.CodCal) CodCal, MAX(c.DatPag) DatPag,
       l.USU_SitLib, l.USU_DatIni, l.USU_UsuLib, l.USU_DatGra, l.USU_ObsLib,
       CASE WHEN l.USU_NumEmp IS NULL OR l.USU_SitLib = 0 THEN 'BLOQUEADO'
            WHEN l.USU_DatIni > TRUNC(SYSDATE)              THEN 'AGENDADO'
            ELSE 'LIBERADO' END Situacao
  FROM VETORH.R044CAL c
  LEFT JOIN VETORH.USU_TLIBHOL l ON l.USU_NumEmp = c.NumEmp AND l.USU_PerRef = c.PerRef
 WHERE c.TipCal = 11
   AND c.PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3)
 GROUP BY c.NumEmp, c.PerRef, l.USU_NumEmp, l.USU_SitLib, l.USU_DatIni, l.USU_UsuLib, l.USU_DatGra, l.USU_ObsLib
 ORDER BY c.PerRef DESC, c.NumEmp;

-- ---------------------------------------------------------------------
-- 1. LIBERAR / AGENDAR (tambem desfaz um bloqueio)
--    DatIni = a partir de quando aparece no portal:
--      hoje            -> TRUNC(SYSDATE)
--      data marcada    -> DATE '2026-11-04'
-- ---------------------------------------------------------------------
MERGE INTO VETORH.USU_TLIBHOL l
USING (SELECT x.NumEmp, x.PerRef,
              x.DatIni, x.Usu, x.Obs
         FROM (SELECT 3                       NumEmp,  -- <-- TROCAR empresa
                      DATE '2026-09-01'       PerRef,  -- <-- TROCAR competencia (sempre dia 01)
                      TRUNC(SYSDATE)          DatIni,  -- <-- TROCAR (ver acima)
                      'ygor.adm'              Usu,     -- <-- TROCAR seu usuario de rede
                      'Contingencia: RH pediu' Obs     -- <-- TROCAR quem pediu / motivo (ate 60)
                 FROM dual) x) s
   ON (l.USU_NumEmp = s.NumEmp AND l.USU_PerRef = s.PerRef)
 WHEN MATCHED THEN UPDATE SET
      l.USU_SitLib = 1, l.USU_DatIni = TRUNC(s.DatIni),
      l.USU_UsuLib = s.Usu, l.USU_DatGra = TRUNC(SYSDATE), l.USU_ObsLib = SUBSTR(s.Obs, 1, 60)
 WHEN NOT MATCHED THEN INSERT
      (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib)
      VALUES (s.NumEmp, s.PerRef, TRUNC(s.DatIni), 1, s.Usu, TRUNC(SYSDATE), SUBSTR(s.Obs, 1, 60));
-- Esperado: 1 linha. Confira com o bloco 0 antes do COMMIT (bloco 3).
-- Antes, confira no bloco 0 se a competencia tem folha calculada (sem folha nao ha o que liberar).

-- ---------------------------------------------------------------------
-- 2. BLOQUEAR / REVERTER LIBERACAO (volta a "Em breve" no portal)
-- ---------------------------------------------------------------------
UPDATE VETORH.USU_TLIBHOL
   SET USU_SitLib = 0,
       USU_UsuLib = 'ygor.adm',                                   -- <-- TROCAR seu usuario
       USU_DatGra = TRUNC(SYSDATE),
       USU_ObsLib = SUBSTR('Contingencia: motivo do bloqueio', 1, 60) -- <-- TROCAR motivo
 WHERE USU_NumEmp = 3                                             -- <-- TROCAR empresa
   AND USU_PerRef = DATE '2026-09-01';                            -- <-- TROCAR competencia
-- Esperado: 1 linha. 0 linhas = ja estava bloqueado (sem registro): nada a fazer.

-- ---------------------------------------------------------------------
-- 3. GRAVAR (ou ROLLBACK; para desistir)
-- ---------------------------------------------------------------------
COMMIT;
