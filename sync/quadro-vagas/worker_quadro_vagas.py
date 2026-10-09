"""Quadro de Vagas (FPRF307) — worker sob demanda Oracle/Sapiens -> Supabase.

Roda na TECNOLIMP12. Fica ouvindo a fila central.qv_solicitacoes; quando alguém
clica em "Gerar" na Central, pega a solicitação, consulta o Oracle (só leitura)
e grava o resultado na mesma linha. Não há carga agendada.

Regras herdadas do FPRF307:
  - colaborador no local histórico da data de emissão (R038HLO) e SitAfa <> 7;
  - Autorizado = R080QUD.VagGer da competência do MÊS ATUAL (igual ao Senior);
  - Efetivo    = R080EFD.VagGer da competência mais recente;
  - uma linha em branco por colaborador ativo no cargo/local (preenchimento à caneta);
  - cargos/locais do quadro do mês sem colaborador ativo também saem, com uma linha por vaga autorizada.

Uso:
  python worker_quadro_vagas.py                      # serviço (loop)
  python worker_quadro_vagas.py --teste --empresa 3 --local 3.111== [--data 2026-10-05]
  python worker_quadro_vagas.py --diagnostico        # colunas das tabelas usadas
"""
import argparse
import calendar
import datetime as dt
import json
import logging
import os
import re
import sys
import time
from logging.handlers import RotatingFileHandler

import oracledb
import requests

INTERVALO = float(os.environ.get("QV_INTERVALO", "3"))
CAMPO_TITULO_CARGO = os.environ.get("QV_CAMPO_TITULO_CARGO", "TitRed")  # TitRed (como no FPRF307) ou TitCar
RE_EMPRESAS = re.compile(r"^\d{1,4}(-\d{1,4})?(,\d{1,4}(-\d{1,4})?)*$")
RE_LOCAIS = re.compile(r"^(\d+(\.\d+)*(==)?(,\d+(\.\d+)*(==)?)*)?$")
TABELAS = ("R034FUN", "R038HLO", "R016HIE", "R016ORN", "R024CAR", "R080QUD", "R080EFD")

log = logging.getLogger("quadro_vagas")


def configurar_log():
    pasta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
    os.makedirs(pasta, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    arq = RotatingFileHandler(os.path.join(pasta, "worker_quadro_vagas.log"), maxBytes=2_000_000, backupCount=5, encoding="utf-8")
    arq.setFormatter(fmt)
    tela = logging.StreamHandler()
    tela.setFormatter(fmt)
    log.addHandler(arq)
    log.addHandler(tela)
    log.setLevel(logging.INFO)


def env(nome):
    valor = os.environ.get(nome)
    if not valor:
        raise SystemExit(f"Variável {nome} não definida (ver credenciais.bat).")
    return valor


# ---------------------------------------------------------------- Oracle
def conectar_oracle():
    pasta_client = os.environ.get("ORACLE_CLIENT_DIR")
    if pasta_client and not getattr(conectar_oracle, "thick", False):
        oracledb.init_oracle_client(lib_dir=pasta_client)  # Oracle antigo (< 12.1) exige modo thick
        conectar_oracle.thick = True
    # Padrão da TECNOLIMP12: ORACLE_HOST/PORT/SID no credenciais.bat (ORACLE_DSN só se for usado)
    dsn = os.environ.get("ORACLE_DSN") or oracledb.makedsn(
        env("ORACLE_HOST"), int(os.environ.get("ORACLE_PORT") or 1521), sid=env("ORACLE_SID"))
    return oracledb.connect(user=env("ORACLE_USER"), password=env("ORACLE_PASSWORD"), dsn=dsn)


_colunas_cache = {}


def colunas(cur, tabela):
    if tabela not in _colunas_cache:
        cur.execute("SELECT DISTINCT column_name FROM all_tab_columns WHERE table_name = :t", t=tabela)
        _colunas_cache[tabela] = {r[0].upper() for r in cur.fetchall()}
    return _colunas_cache[tabela]


def filtro_empresas(texto, binds):
    if not RE_EMPRESAS.match(texto or ""):
        raise ValueError("Empresa inválida.")
    partes = []
    for i, tok in enumerate(texto.split(",")):
        if "-" in tok:
            de, ate = tok.split("-")
            binds[f"e{i}a"], binds[f"e{i}b"] = int(de), int(ate)
            partes.append(f"f.NumEmp BETWEEN :e{i}a AND :e{i}b")
        else:
            binds[f"e{i}"] = int(tok)
            partes.append(f"f.NumEmp = :e{i}")
    return "(" + " OR ".join(partes) + ")"


def filtro_locais(texto, binds):
    texto = texto or ""
    if not RE_LOCAIS.match(texto):
        raise ValueError("Local inválido.")
    if not texto:
        return ""
    partes = []
    for i, tok in enumerate(texto.split(",")):
        if tok.endswith("=="):  # "3.111==" = o próprio local e todos abaixo dele
            base = tok[:-2]
            binds[f"l{i}"], binds[f"l{i}p"] = base, base + ".%"
            partes.append(f"(hie.CodLoc = :l{i} OR hie.CodLoc LIKE :l{i}p)")
        else:
            binds[f"l{i}"] = tok
            partes.append(f"hie.CodLoc = :l{i}")
    return " AND (" + " OR ".join(partes) + ")"


def competencia_atual(hoje=None):
    hoje = hoje or dt.date.today()
    ultimo = calendar.monthrange(hoje.year, hoje.month)[1]
    return dt.datetime(hoje.year, hoje.month, 1), dt.datetime(hoje.year, hoje.month, ultimo, 23, 59, 59)


def chave_codloc(codloc):
    return [int(p) if p.isdigit() else p for p in str(codloc or "").split(".")]


def gerar(con, data_emissao, empresas, locais):
    cur = con.cursor()
    data = dt.datetime.combine(data_emissao, dt.time())
    binds = {"dat": data}
    f_emp = filtro_empresas(empresas, binds)
    f_loc = filtro_locais(locais, binds)
    f_emp_h = f_emp.replace("f.NumEmp", "h.NumEmp")

    # Hierarquia (R016HIE) e cadastro do local (R016ORN): adapta ao que existe no banco.
    hie_hist = ""
    if "DATINI" in colunas(cur, "R016HIE"):
        hie_hist = (" AND hie.DatIni = (SELECT MAX(h3.DatIni) FROM R016HIE h3"
                    " WHERE h3.TabOrg = hie.TabOrg AND h3.NumLoc = hie.NumLoc AND h3.DatIni <= :dat)")
    orn_tab = " AND orn.TabOrg = hlo.TabOrg" if "TABORG" in colunas(cur, "R016ORN") else ""
    endereco = "orn.USU_EndLoc" if "USU_ENDLOC" in colunas(cur, "R016ORN") else "NULL"
    titulo = CAMPO_TITULO_CARGO if CAMPO_TITULO_CARGO.upper() in colunas(cur, "R024CAR") else "TitCar"

    sql = f"""
        WITH hlo AS (
          SELECT h.NumEmp, h.TipCol, h.NumCad, h.TabOrg, h.NumLoc
            FROM R038HLO h
           WHERE {f_emp_h} AND h.DatAlt = (SELECT MAX(h2.DatAlt) FROM R038HLO h2
                              WHERE h2.NumEmp = h.NumEmp AND h2.TipCol = h.TipCol
                                AND h2.NumCad = h.NumCad AND h2.DatAlt <= :dat))
        SELECT f.NumEmp, hlo.TabOrg, hlo.NumLoc, hie.CodLoc, MAX(orn.NomLoc), MAX({endereco}),
               f.CodCar, MAX(car.{titulo}),
               COUNT(DISTINCT f.TipCol || '-' || f.NumCad)  -- à prova de duplicidade nos joins
          FROM R034FUN f
          JOIN hlo ON hlo.NumEmp = f.NumEmp AND hlo.TipCol = f.TipCol AND hlo.NumCad = f.NumCad
          JOIN R016HIE hie ON hie.TabOrg = hlo.TabOrg AND hie.NumLoc = hlo.NumLoc{hie_hist}
          LEFT JOIN R016ORN orn ON orn.NumLoc = hlo.NumLoc{orn_tab}
          LEFT JOIN R024CAR car ON car.EstCar = f.EstCar AND car.CodCar = f.CodCar
         WHERE f.SitAfa <> 7 AND {f_emp}{f_loc}
         GROUP BY f.NumEmp, hlo.TabOrg, hlo.NumLoc, hie.CodLoc, f.CodCar"""
    cur.execute(sql, binds)
    linhas = cur.fetchall()

    # Quadro do mês atual (R080QUD) nos mesmos locais: dá o Autorizado e também lista as
    # vagas de cargos/locais ainda sem colaborador ativo (ex.: posto novo, vaga em aberto).
    ini, fim = competencia_atual()
    bq = {"dat": data, "ini": ini, "fim": fim}
    f_emp_q = filtro_empresas(empresas, bq).replace("f.NumEmp", "q.NumEmp")
    f_loc_q = filtro_locais(locais, bq)
    cur.execute(f"""
        SELECT q.NumEmp, q.TabOrg, q.NumLoc, hie.CodLoc, MAX(orn.NomLoc), MAX({endereco}),
               q.CodCar, MAX(car.{titulo}), MAX(q.VagGer)
          FROM R080QUD q
          JOIN R016HIE hie ON hie.TabOrg = q.TabOrg AND hie.NumLoc = q.NumLoc{hie_hist}
          LEFT JOIN R016ORN orn ON orn.NumLoc = q.NumLoc{orn_tab.replace("hlo.", "q.")}
          LEFT JOIN R024CAR car ON car.EstCar = q.EstCar AND car.CodCar = q.CodCar
         WHERE q.CmpQua BETWEEN :ini AND :fim AND {f_emp_q}{f_loc_q}
         GROUP BY q.NumEmp, q.TabOrg, q.NumLoc, hie.CodLoc, q.CodCar""", bq)
    quadro = cur.fetchall()
    if not linhas and not quadro:
        return {"data_emissao": data_emissao.isoformat(), "competencia": ini.strftime("%Y-%m"), "locais": []}
    autorizado = {(r[0], r[1], r[2], str(r[6]).strip()): r[8] for r in quadro}

    # Efetivo: competência mais recente
    be = {}
    f_emp_e = filtro_empresas(empresas, be).replace("f.NumEmp", "q.NumEmp")
    cur.execute(f"""SELECT NumEmp, TabOrg, NumLoc, CodCar, VagGer FROM (
                      SELECT q.NumEmp, q.TabOrg, q.NumLoc, q.CodCar, q.VagGer,
                             ROW_NUMBER() OVER (PARTITION BY q.NumEmp, q.TabOrg, q.NumLoc, q.CodCar
                                                ORDER BY q.CmpQua DESC) rn
                        FROM R080EFD q WHERE {f_emp_e}) WHERE rn = 1""", be)
    efetivo = {(r[0], r[1], r[2], str(r[3]).strip()): r[4] for r in cur.fetchall()}

    locais_out, vistos = {}, set()

    def adicionar(numemp, taborg, numloc, codloc, nomloc, endloc, codcar, tit, qtd_linhas):
        codcar = str(codcar or "").strip()
        k = (numemp, taborg, numloc, codcar)
        if k in vistos:
            return
        vistos.add(k)
        local = locais_out.setdefault((numemp, taborg, numloc), {
            "codloc": str(codloc or "").strip(), "nomloc": (nomloc or "").strip(),
            "endereco": (endloc or "").strip(), "cargos": []})
        local["cargos"].append({
            "codcar": codcar, "titulo": (tit or "").strip(),
            "autorizado": int(autorizado.get(k) or 0), "efetivo": int(efetivo.get(k) or 0),
            "linhas": int(qtd_linhas)})

    # 1) cargos com colaborador ativo: uma linha em branco por colaborador (como no Senior)
    for numemp, taborg, numloc, codloc, nomloc, endloc, codcar, tit, qtd in linhas:
        adicionar(numemp, taborg, numloc, codloc, nomloc, endloc, codcar, tit, qtd)
    # 2) vagas do quadro sem colaborador: uma linha em branco por vaga autorizada
    for numemp, taborg, numloc, codloc, nomloc, endloc, codcar, tit, vag in quadro:
        if (vag or 0) > 0:
            adicionar(numemp, taborg, numloc, codloc, nomloc, endloc, codcar, tit, vag)

    resultado = sorted(locais_out.items(), key=lambda kv: (chave_codloc(kv[1]["codloc"]), kv[0][0]))
    for _, local in resultado:
        local["cargos"].sort(key=lambda c: (c["titulo"], c["codcar"]))
    return {"data_emissao": data_emissao.isoformat(), "competencia": ini.strftime("%Y-%m"),
            "locais": [l for _, l in resultado]}


# ---------------------------------------------------------------- Supabase
class Fila:
    def __init__(self):
        self.url = env("SUPABASE_URL").rstrip("/") + "/rest/v1/"
        chave = os.environ.get("SUPABASE_SERVICE_KEY") or env("SUPABASE_SERVICE_ROLE_KEY")
        self.s = requests.Session()
        self.s.headers.update({"apikey": chave, "Authorization": "Bearer " + chave,
                               "Content-Type": "application/json", "Content-Profile": "central",
                               "Accept-Profile": "central"})

    def rpc(self, nome):
        r = self.s.post(self.url + "rpc/" + nome, json={}, timeout=30)
        r.raise_for_status()
        return r.json() if r.content else None

    def concluir(self, id_, status, resultado=None, mensagem=None):
        corpo = {"status": status, "resultado": resultado, "mensagem": mensagem,
                 "atualizado_em": dt.datetime.now(dt.timezone.utc).isoformat()}
        r = self.s.patch(self.url + "qv_solicitacoes", params={"id": "eq." + id_}, json=corpo, timeout=60)
        r.raise_for_status()


def processar(fila, sol):
    inicio = time.time()
    log.info("Solicitação %s: empresa=%s local=%s data=%s", sol["id"], sol["empresas"], sol["locais"], sol["data_emissao"])
    try:
        con = conectar_oracle()
        try:
            dados = gerar(con, dt.date.fromisoformat(sol["data_emissao"]), sol["empresas"], sol["locais"])
        finally:
            con.close()
        fila.concluir(sol["id"], "concluido", resultado=dados)
        log.info("Solicitação %s concluída: %d locais em %.1fs", sol["id"], len(dados["locais"]), time.time() - inicio)
    except Exception as e:  # erro vai para a tela; detalhe técnico só no log
        log.exception("Solicitação %s falhou", sol["id"])
        msg = str(e) if isinstance(e, ValueError) else "Falha ao consultar o Senior. Detalhes no log do serviço (TECNOLIMP12)."
        try:
            fila.concluir(sol["id"], "erro", mensagem=msg)
        except Exception:
            log.exception("Não foi possível registrar o erro da solicitação %s", sol["id"])


def servico():
    fila = Fila()
    log.info("Worker Quadro de Vagas iniciado (intervalo %.0fs)", INTERVALO)
    ultima_manutencao = 0.0
    while True:
        try:
            if time.time() - ultima_manutencao > 3600:
                fila.rpc("qv_manutencao")
                ultima_manutencao = time.time()
            for sol in fila.rpc("qv_proxima") or []:
                processar(fila, sol)
        except requests.RequestException as e:
            log.warning("Supabase indisponível: %s", e)
            time.sleep(15)
        except Exception:
            log.exception("Erro inesperado no laço principal")
            time.sleep(15)
        time.sleep(INTERVALO)


def diagnostico():
    con = conectar_oracle()
    cur = con.cursor()
    for t in TABELAS:
        print(f"{t}: {', '.join(sorted(colunas(cur, t))) or '(não encontrada)'}")
    con.close()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--teste", action="store_true", help="gera uma vez e imprime o JSON (não usa o Supabase)")
    p.add_argument("--diagnostico", action="store_true", help="lista as colunas das tabelas usadas")
    p.add_argument("--empresa", default="")
    p.add_argument("--local", default="")
    p.add_argument("--data", default=dt.date.today().isoformat())
    a = p.parse_args()
    configurar_log()
    if a.diagnostico:
        return diagnostico()
    if a.teste:
        con = conectar_oracle()
        try:
            dados = gerar(con, dt.date.fromisoformat(a.data), a.empresa.replace(" ", ""), a.local.replace(" ", "").replace('"', ""))
        finally:
            con.close()
        sys.stdout.reconfigure(encoding="utf-8")  # "> teste.json" no Windows sairia em cp1252
        print(json.dumps(dados, ensure_ascii=False, indent=2))
        return None
    return servico()


if __name__ == "__main__":
    sys.exit(main())
