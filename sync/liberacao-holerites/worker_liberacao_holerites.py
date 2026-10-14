"""Liberação de holerites RH 24h — integrador sob demanda Central -> Sapiens/Oracle.

Roda na TECNOLIMP12. Fica ouvindo a fila central.lh_pedidos (consulta barata ao
Supabase); quando a T.I. clica em Liberar / Agendar / Bloquear / Atualizar no painel:
  1) grava a decisão na USU_TLIBHOL (única tabela do Sapiens em que escreve);
  2) informa ao Supabase como as linhas ficaram (histórico "painel");
  3) relê R044CAL + USU_TLIBHOL e atualiza o espelho do painel. O que mudou
     sem passar pelo painel (SQL de contingência) entra como "fora do painel".
O Oracle só é tocado quando chega pedido (e uma leitura ao iniciar o serviço).

Regras (docs/plano-liberacao.md):
  - sem linha na USU_TLIBHOL = bloqueado; bloquear = USU_SitLib 0 (nunca apaga);
  - "a partir de" sempre gravada com TRUNC; agendar no padrão = DatPag - 1;
  - folha = R044CAL TipCal 11, CodCal mais recente da competência (igual ao bloco 5);
  - janela = do mês atual até 3 meses atrás (as 3 posições do portal + a próxima folha).

Uso:
  python worker_liberacao_holerites.py                 # serviço (loop)
  python worker_liberacao_holerites.py --diagnostico   # colunas e permissões no Oracle
  python worker_liberacao_holerites.py --leitura       # imprime o que seria espelhado (não grava nada)
  python worker_liberacao_holerites.py --espelhar      # relê o Sapiens e atualiza o painel uma vez
"""
import argparse
import datetime as dt
import json
import logging
import os
import sys
import time
from logging.handlers import RotatingFileHandler

import requests

INTERVALO = float(os.environ.get("LH_INTERVALO", "3"))
ACOES = ("liberar", "agendar", "agendar_padrao", "bloquear", "atualizar")
MAX_ALVOS = 20

log = logging.getLogger("liberacao_holerites")


def configurar_log():
    pasta = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
    os.makedirs(pasta, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    arq = RotatingFileHandler(os.path.join(pasta, "worker_liberacao_holerites.log"), maxBytes=2_000_000,
                              backupCount=5, encoding="utf-8")
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


def inicio_janela(hoje=None):
    """1º dia do mês, 3 meses atrás (posição 3 do portal)."""
    hoje = hoje or dt.date.today()
    mes = hoje.month - 3
    ano = hoje.year
    if mes < 1:
        mes += 12
        ano -= 1
    return dt.date(ano, mes, 1)


def data(valor):
    """date de um valor do Oracle (datetime) ou do Supabase (texto ISO)."""
    if valor is None:
        return None
    if isinstance(valor, dt.datetime):
        return valor.date()
    if isinstance(valor, dt.date):
        return valor
    return dt.date.fromisoformat(str(valor)[:10])


def validar_alvos(alvos):
    if not isinstance(alvos, list) or not 1 <= len(alvos) <= MAX_ALVOS:
        raise ValueError(f"Informe de 1 a {MAX_ALVOS} empresas/competências.")
    saida = []
    for a in alvos:
        emp, per = int(a["emp"]), data(a["per"])
        if not 1 <= emp <= 9999 or per.day != 1:
            raise ValueError("Empresa/competência inválida.")
        if (emp, per) not in saida:
            saida.append((emp, per))
    return saida


# ---------------------------------------------------------------- Oracle
class Sapiens:
    """Acesso ao Oracle: lê R044CAL/USU_TLIBHOL e escreve só na USU_TLIBHOL (binds sempre)."""

    def __init__(self, con):
        self.con = con
        dono = os.environ.get("LH_ESQUEMA", "").strip().upper()  # dono das tabelas, se o usuário for dedicado
        if dono and not dono.replace("_", "").isalnum():
            raise SystemExit("LH_ESQUEMA inválido.")
        self.p = dono + "." if dono else ""

    @classmethod
    def conectar(cls):
        import oracledb  # importado aqui para os testes rodarem sem o driver
        pasta_client = os.environ.get("ORACLE_CLIENT_DIR")
        if pasta_client and not getattr(cls, "_thick", False):
            oracledb.init_oracle_client(lib_dir=pasta_client)  # Oracle antigo (< 12.1) exige modo thick
            cls._thick = True
        dsn = os.environ.get("ORACLE_DSN") or oracledb.makedsn(
            env("ORACLE_HOST"), int(os.environ.get("ORACLE_PORT") or 1521), sid=env("ORACLE_SID"))
        # usuário dedicado (decisão 1: grant só na USU_TLIBHOL + SELECT na R044CAL); sem ele, usa o do sync
        usuario = os.environ.get("LH_ORACLE_USER") or env("ORACLE_USER")
        senha = os.environ.get("LH_ORACLE_PASSWORD") or env("ORACLE_PASSWORD")
        if not os.environ.get("LH_ORACLE_USER"):
            log.warning("LH_ORACLE_USER não definido: usando o usuário do sync (%s).", usuario)
        return cls(oracledb.connect(user=usuario, password=senha, dsn=dsn))

    def fechar(self):
        self.con.close()

    def folhas(self, desde):
        """Folha mensal mais recente (maior CodCal) por empresa + competência."""
        cur = self.con.cursor()
        cur.execute(f"SELECT NumEmp, PerRef, CodCal, DatPag FROM {self.p}R044CAL "
                    "WHERE TipCal = 11 AND PerRef >= :desde", desde=dt.datetime.combine(desde, dt.time()))
        maior = {}
        for emp, per, cod, pag in cur.fetchall():
            chave = (int(emp), data(per))
            if chave not in maior or int(cod) > maior[chave][0]:
                maior[chave] = (int(cod), data(pag))
        return [{"emp": e, "per": p.isoformat(), "codcal": c, "datpag": d.isoformat()}
                for (e, p), (c, d) in sorted(maior.items())]

    def liberacoes(self, desde):
        cur = self.con.cursor()
        cur.execute(f"SELECT USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib "
                    f"FROM {self.p}USU_TLIBHOL WHERE USU_PerRef >= :desde",
                    desde=dt.datetime.combine(desde, dt.time()))
        return [self._linha(r) for r in cur.fetchall()]

    @staticmethod
    def _linha(r):
        emp, per, ini, sit, usu, gra, obs = r
        return {"emp": int(emp), "per": data(per).isoformat(), "sit": int(sit),
                "ini": data(ini).isoformat() if ini else None, "usu": (usu or "").strip(),
                "gra": data(gra).isoformat() if gra else None, "obs": (obs or "").strip()}

    def linha(self, emp, per):
        cur = self.con.cursor()
        cur.execute(f"SELECT USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib "
                    f"FROM {self.p}USU_TLIBHOL WHERE USU_NumEmp = :emp AND USU_PerRef = :per",
                    emp=emp, per=dt.datetime.combine(per, dt.time()))
        r = cur.fetchone()
        return self._linha(r) if r else None

    def data_pagamento(self, emp, per):
        cur = self.con.cursor()
        cur.execute(f"SELECT DatPag FROM {self.p}R044CAL WHERE NumEmp = :emp AND TipCal = 11 AND PerRef = :per "
                    "ORDER BY CodCal DESC", emp=emp, per=dt.datetime.combine(per, dt.time()))
        r = cur.fetchone()
        return data(r[0]) if r else None

    def liberar(self, emp, per, ini, usu, obs):
        cur = self.con.cursor()
        cur.execute(
            f"MERGE INTO {self.p}USU_TLIBHOL l "
            "USING (SELECT :emp NumEmp, :per PerRef FROM dual) s "
            "ON (l.USU_NumEmp = s.NumEmp AND l.USU_PerRef = s.PerRef) "
            "WHEN MATCHED THEN UPDATE SET l.USU_SitLib = 1, l.USU_DatIni = TRUNC(:ini), "
            "  l.USU_UsuLib = :usu, l.USU_DatGra = TRUNC(SYSDATE), l.USU_ObsLib = :obs "
            "WHEN NOT MATCHED THEN INSERT (USU_NumEmp, USU_PerRef, USU_DatIni, USU_SitLib, USU_UsuLib, USU_DatGra, USU_ObsLib) "
            "  VALUES (:emp, :per, TRUNC(:ini), 1, :usu, TRUNC(SYSDATE), :obs)",
            emp=emp, per=dt.datetime.combine(per, dt.time()), ini=dt.datetime.combine(ini, dt.time()),
            usu=usu[:30], obs=(obs or " ")[:60])

    def bloquear(self, emp, per, usu, obs):
        cur = self.con.cursor()
        cur.execute(f"UPDATE {self.p}USU_TLIBHOL SET USU_SitLib = 0, USU_UsuLib = :usu, "
                    "USU_DatGra = TRUNC(SYSDATE), USU_ObsLib = :obs "
                    "WHERE USU_NumEmp = :emp AND USU_PerRef = :per",
                    emp=emp, per=dt.datetime.combine(per, dt.time()), usu=usu[:30], obs=(obs or " ")[:60])
        return cur.rowcount  # 0 = não tinha linha = já estava bloqueado

    def commit(self):
        self.con.commit()

    def rollback(self):
        self.con.rollback()


# ---------------------------------------------------------------- Supabase
class Fila:
    def __init__(self):
        self.url = env("SUPABASE_URL").rstrip("/") + "/rest/v1/"
        chave = os.environ.get("SUPABASE_SERVICE_KEY") or env("SUPABASE_SERVICE_ROLE_KEY")
        self.s = requests.Session()
        self.s.headers.update({"apikey": chave, "Authorization": "Bearer " + chave,
                               "Content-Type": "application/json", "Content-Profile": "central",
                               "Accept-Profile": "central"})

    def rpc(self, nome, **corpo):
        r = self.s.post(self.url + "rpc/" + nome, json=corpo, timeout=60)
        r.raise_for_status()
        return r.json() if r.content else None

    def proximo(self):
        return self.rpc("lh_proximo") or []

    def concluir(self, id_, status, mensagem=None, aplicados=None):
        self.rpc("lh_concluir", p_id=id_, p_status=status, p_mensagem=mensagem, p_aplicados=aplicados or [])

    def espelhar(self, desde, folhas, liberacoes):
        return self.rpc("lh_espelhar", p_desde=desde.isoformat(), p_folhas=folhas, p_liberacoes=liberacoes)

    def manutencao(self):
        self.rpc("lh_manutencao")


# ---------------------------------------------------------------- regras
def aplicar(sap, ped, hoje=None):
    """Grava o pedido na USU_TLIBHOL numa transação só. Devolve as linhas como ficaram."""
    hoje = hoje or dt.date.today()
    acao = ped["acao"]
    if acao not in ACOES:
        raise ValueError("Ação inválida.")
    if acao == "atualizar":
        return []
    usu, obs = ped["usuario_login"], (ped.get("obs") or "").strip()
    alvos = validar_alvos(ped.get("alvos"))
    aplicados = []
    try:
        for emp, per in alvos:
            if acao == "bloquear":
                if sap.bloquear(emp, per, usu, obs) == 0:
                    continue  # sem registro = já bloqueado
            else:
                if acao == "agendar_padrao":
                    pag = sap.data_pagamento(emp, per)
                    if not pag:
                        raise ValueError(f"Empresa {emp} sem folha calculada em {per:%m/%Y}.")
                    ini = pag - dt.timedelta(days=1)
                elif acao == "liberar":
                    ini = hoje
                else:
                    ini = data(ped.get("data_ini"))
                    if not ini or ini <= hoje:
                        raise ValueError("A data do agendamento precisa ser depois de hoje.")
                sap.liberar(emp, per, ini, usu, obs)
            linha = sap.linha(emp, per)
            if linha:
                aplicados.append({k: linha[k] for k in ("emp", "per", "sit", "ini", "gra")})
        sap.commit()
    except Exception:
        sap.rollback()
        raise
    return aplicados


def espelhar(sap, fila, hoje=None):
    desde = inicio_janela(hoje)
    n = fila.espelhar(desde, sap.folhas(desde), sap.liberacoes(desde))
    if n:
        log.warning("%s alteração(ões) feitas fora do painel registradas no histórico.", n)
    return n


def processar(fila, ped, abrir_sapiens=None):
    abrir_sapiens = abrir_sapiens or Sapiens.conectar
    inicio = time.time()
    log.info("Pedido %s: %s por %s, alvos=%s, data=%s", ped["id"], ped["acao"], ped["usuario_login"],
             json.dumps(ped.get("alvos")), ped.get("data_ini"))
    sap = None
    try:
        sap = abrir_sapiens()
        aplicados = aplicar(sap, ped)
        # Oracle já gravou: se o Supabase falhar aqui, a próxima leitura registra como "fora do painel"
        fila.concluir(ped["id"], "aplicado", aplicados=aplicados)
        espelhar(sap, fila)
        log.info("Pedido %s aplicado: %d linha(s) em %.1fs", ped["id"], len(aplicados), time.time() - inicio)
    except Exception as e:  # erro vai para a tela; detalhe técnico só no log
        log.exception("Pedido %s falhou", ped["id"])
        msg = str(e) if isinstance(e, ValueError) else "Falha ao gravar no Sapiens. Detalhes no log do integrador (TECNOLIMP12)."
        try:
            fila.concluir(ped["id"], "erro", mensagem=msg)
        except Exception:
            log.exception("Não foi possível registrar o erro do pedido %s", ped["id"])
    finally:
        if sap:
            sap.fechar()


def servico():
    fila = Fila()
    log.info("Integrador Liberação de Holerites iniciado (intervalo %.0fs)", INTERVALO)
    try:  # painel começa com o Sapiens atual
        sap = Sapiens.conectar()
        try:
            espelhar(sap, fila)
        finally:
            sap.fechar()
    except Exception:
        log.exception("Leitura inicial do Sapiens falhou; segue ouvindo a fila")
    ultima_manutencao = 0.0
    while True:
        try:
            if time.time() - ultima_manutencao > 3600:
                fila.manutencao()
                ultima_manutencao = time.time()
            for ped in fila.proximo():
                processar(fila, ped)
        except requests.RequestException as e:
            log.warning("Supabase indisponível: %s", e)
            time.sleep(15)
        except Exception:
            log.exception("Erro inesperado no laço principal")
            time.sleep(15)
        time.sleep(INTERVALO)


def diagnostico():
    sap = Sapiens.conectar()
    cur = sap.con.cursor()
    for t in ("R044CAL", "USU_TLIBHOL"):
        cur.execute("SELECT owner, LISTAGG(column_name, ', ') WITHIN GROUP (ORDER BY column_id) "
                    "FROM all_tab_columns WHERE table_name = :t GROUP BY owner", t=t)
        linhas = cur.fetchall()
        print(f"{t}: " + ("; ".join(f"[{o}] {c}" for o, c in linhas) if linhas else "(não encontrada ou sem acesso)"))
    cur.execute("SELECT privilege FROM all_tab_privs WHERE table_name = 'USU_TLIBHOL' AND grantee = USER")
    print("Privilégios na USU_TLIBHOL (usuário dedicado):", ", ".join(r[0] for r in cur.fetchall()) or "(nenhum grant explícito)")
    desde = inicio_janela()
    print(f"Janela desde {desde:%m/%Y}: {len(sap.folhas(desde))} folha(s), {len(sap.liberacoes(desde))} liberação(ões)")
    sap.fechar()


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--diagnostico", action="store_true", help="colunas, permissões e contagens no Oracle")
    p.add_argument("--leitura", action="store_true", help="imprime o que seria espelhado (não grava nada)")
    p.add_argument("--espelhar", action="store_true", help="relê o Sapiens e atualiza o painel uma vez")
    a = p.parse_args()
    configurar_log()
    if a.diagnostico:
        return diagnostico()
    if a.leitura:
        sap = Sapiens.conectar()
        try:
            desde = inicio_janela()
            dados = {"desde": desde.isoformat(), "folhas": sap.folhas(desde), "liberacoes": sap.liberacoes(desde)}
        finally:
            sap.fechar()
        sys.stdout.reconfigure(encoding="utf-8")
        print(json.dumps(dados, ensure_ascii=False, indent=2))
        return None
    if a.espelhar:
        sap = Sapiens.conectar()
        try:
            print("Alterações fora do painel:", espelhar(sap, Fila()))
        finally:
            sap.fechar()
        return None
    return servico()


if __name__ == "__main__":
    sys.exit(main())
