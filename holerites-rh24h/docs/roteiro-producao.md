# Roteiro de produção — Liberação de Holerites

HML validado em 14/10/2026: clique no painel, fila, integrador (`TEC_LIBHOL`), gravação na `USU_TLIBHOL` e desfazer.
Fazer na ordem. Cada etapa tem um **Conferir** e só se avança com ele ok.

| # | Onde | O quê |
|---|---|---|
| 1 | VM Ubuntu (Supabase PROD) | Migration 007 |
| 2 | TECNOLIMP12 | Integrador apontando para PROD |
| 3 | tecnolimp15 (IIS) | Painel na Central |
| 4 | TECNOLIMP12 | Serviço no Agendador |
| 5 | Senior (Modelo Gerador) | Pré-seleção das demais empresas |
| 6 | Navegador | Teste final |

---

## 1. Supabase PROD — migration 007
Extrair o zip na **Área de Trabalho** (deve existir `Desktop\liberacao-holerites-producao\1-supabase-vm\007_liberacao_holerites.sql`; se o Windows criar a pasta duas vezes, mover a de dentro para a Área de Trabalho).

**PowerShell do Windows** — copiar para a VM Ubuntu e entrar nela:
```powershell
scp "$env:USERPROFILE\Desktop\liberacao-holerites-producao\1-supabase-vm\007_liberacao_holerites.sql" admtecnolimp@supabase.tecnolimp.local:~/
ssh admtecnolimp@supabase.tecnolimp.local
```
(OneDrive: trocar `Desktop` por `OneDrive\Desktop`.) Pede a senha do `admtecnolimp` duas vezes (scp e ssh).

**VM Ubuntu** (já dentro do ssh):
```bash
ls -l ~/007_liberacao_holerites.sql
sudo docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < ~/007_liberacao_holerites.sql
```
Na tela: uma sequência de `CREATE TABLE`, `CREATE FUNCTION`, `GRANT`, `INSERT 0 1`, `DO`, sem `ERROR`.

**Conferir** (VM Ubuntu):
```bash
sudo docker exec -i supabase-db psql -U supabase_admin -d postgres -c "select slug, publico from central.relatorios where slug = 'liberacao-holerites';"
sudo docker exec -i supabase-db psql -U supabase_admin -d postgres -c "select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'central' and p.proname like 'lh\_%';"
sudo /usr/local/sbin/backup-supabase.sh
exit
```
Esperado: 1 linha com `publico = f`; contagem `10`. `0 rows` no primeiro = não existe a área `ti` na PROD: avisar antes de seguir.

## 2. Integrador → PROD (TECNOLIMP12)
1. Substituir na pasta `C:\Automações\08 - Liberação holerite` os arquivos de `2-integrador/` (**não** existe `credenciais.bat` no zip; o seu fica).
2. No `credenciais.bat`, trocar o Supabase do HML pelo da PROD:
   ```bat
   set "SUPABASE_URL=http://supabase.tecnolimp.local:8000"
   set "SUPABASE_SERVICE_KEY=<service_role da VM>"
   set "NO_PROXY=supabase.tecnolimp.local,localhost,127.0.0.1"
   ```
   A chave da PROD já está na máquina: é a mesma do `credenciais.bat` do Quadro de Vagas. Copiar de lá; nunca colar em chat ou e-mail.
3. Cmd novo:
   ```bat
   cd /d "C:\Automações\08 - Liberação holerite"
   call credenciais.bat
   "%PYEXE%" worker_liberacao_holerites.py --diagnostico
   "%PYEXE%" worker_liberacao_holerites.py --espelhar
   ```
**Conferir:** o diagnóstico mostra `Privilégios na USU_TLIBHOL (TEC_LIBHOL): INSERT, SELECT, UPDATE`; o `--espelhar` termina sem erro (na PROD vazia, as linhas da virada entram como "fora do painel" — esperado).

## 3. Painel na Central (tecnolimp15)
Levar o zip para a **Área de Trabalho da tecnolimp15** e extrair.

**tecnolimp15 — PowerShell como Administrador** (copia só a pasta nova; o `config.js` da PROD não é tocado):
```powershell
robocopy "$env:USERPROFILE\Desktop\liberacao-holerites-producao\3-site\relatorios\liberacao-holerites" "C:\Sites\central\relatorios\liberacao-holerites" /E
Get-ChildItem "C:\Sites\central\relatorios\liberacao-holerites"
```
Na tela: 4 arquivos (`index.html`, `painel.css`, `painel.js`, `tecnolimp-simbolo.png`).
**Conferir:** de outra máquina, Ctrl+F5 em `http://central.apps.tecnolimp.local/relatorios/liberacao-holerites/` com seu login → 6 empresas, set/ago/jul liberados, out "Próxima" bloqueada.
Quem mais da TI precisa usar: Administração › acesso à área T.I. (ou ao relatório). Ninguém fora disso vê o painel.

## 4. Serviço no Agendador (TECNOLIMP12)
PowerShell **como administrador**, na pasta do integrador:
```powershell
powershell -ExecutionPolicy Bypass -File .\instalar_tarefa.ps1
```
Pede o usuário do Windows que roda a tarefa (o mesmo do `PYEXE`).
**Conferir:** `logs\worker_liberacao_holerites.log` com "Integrador ... iniciado"; no painel, "↻ Atualizar do Sapiens" conclui em poucos segundos e o aviso amarelo não aparece.

## 5. Pré-seleção das demais empresas (Senior)
A virada de Tecnolimp, Pontual, DRA e Deltalimp já foi feita. Antes de colar, no **Oracle (DBeaver, Sapiens)**:
```sql
SELECT USU_NumEmp, COUNT(*) meses, MIN(USU_SitLib) sitlib
  FROM VETORH.USU_TLIBHOL
 WHERE USU_PerRef >= ADD_MONTHS(TRUNC(SYSDATE,'MM'), -3) AND USU_PerRef < TRUNC(SYSDATE,'MM')
 GROUP BY USU_NumEmp ORDER BY 1;
```
Esperado: empresas 1, 3, 4, 5, 6, 7 com `meses = 3` e `sitlib = 1`. Empresa faltando → rodar `4-sapiens/virada_demais_empresas.sql` antes (senão o holerite some para todos dela).

Colar a pré-seleção de `4-sapiens/` em cada modelo (substituir a pré-seleção inteira, Consistir, Salvar):

| Empresa | Modelos | Login de teste (sufixo) |
|---|---|---|
| Pontual (3) | FPFF591, 592, 593 | `E` ou `P` |
| Tecnolimp (1) | FPFF691, 692, 693 | sem sufixo |
| Deltalimp (6) | FPFF791, 792, 793 | `L` |
| DRA (5) | FPFF891, 892, 893 | `D` |

**Conferir** por empresa, no portal, com um colaborador ativo desde antes de julho: setembro/agosto/julho abrem; outubro "🔒 Em breve".
**Voltar atrás:** colar a pré-seleção original (`originais/FPFFxxx.OPE.txt` do repositório).

## 6. Teste final (PROD)
No painel PROD, uma empresa, competência "Próxima": **Agendar** para daqui a 7 dias → conferir a linha na `USU_TLIBHOL` → **Bloquear** (volta `SitLib 0`). Histórico mostra as duas ações com o seu usuário.

## Operação no dia a dia
- RH pede → TI agenda (ou "Todas no padrão": cada empresa libera 1 dia antes do pagamento).
- Aviso "integrador não respondeu" → Agendador › *Tecnolimp - Liberacao de Holerites (integrador)* › Executar. Urgência sem painel: `sql_contingencia.sql` e depois "Atualizar do Sapiens".
- Atualizar o integrador: trocar só `.py/.bat/.ps1` e reiniciar a tarefa.
