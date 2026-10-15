"""Teste de ponta a ponta do integrador sem Oracle.

Sapiens falso em memória (R044CAL + USU_TLIBHOL) + funções lh_* reais num Postgres
local com as migrations aplicadas (ver migrations/testes/). Uso:
  PGHOST=/caminho/socket PGPORT=5499 PGDATABASE=vm python testes/teste_integrador.py
"""
import datetime as dt
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import worker_liberacao_holerites as w  # noqa: E402

HOJE = dt.date.today()
TI = "11111111-1111-1111-1111-111111111111"


def psql(sql, papel="service_role", sub=""):
    pre = f"set role {papel}; set request.jwt.claim.role = '{papel}'; set request.jwt.claim.sub = '{sub}';"
    r = subprocess.run(["psql", "-U", "postgres", "-tA", "-v", "ON_ERROR_STOP=1", "-c", pre + sql],
                       capture_output=True, text=True)
    if r.returncode:
        raise RuntimeError(r.stderr.strip())
    return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ""


def j(obj):
    return "$j$" + json.dumps(obj) + "$j$"


class FilaPg:
    """Mesma interface da w.Fila, chamando as funções direto no Postgres."""
    def proximo(self):
        linha = psql("select coalesce(json_agg(p), '[]') from central.lh_proximo() p;")
        return json.loads(linha)

    def concluir(self, id_, status, mensagem=None, aplicados=None):
        msg = "null" if mensagem is None else "$m$" + mensagem + "$m$"
        psql(f"select central.lh_concluir('{id_}', '{status}', {msg}, {j(aplicados or [])}::jsonb);")

    def espelhar(self, desde, folhas, liberacoes):
        return int(psql(f"select central.lh_espelhar('{desde}', {j(folhas)}::jsonb, {j(liberacoes)}::jsonb);"))

    def manutencao(self):
        psql("select central.lh_manutencao();")


class SapiensFalso:
    def __init__(self):
        self.cal = []   # (emp, per, codcal, datpag)
        self.lib = {}   # (emp, per) -> dict
        self.falhar = False
        self.commits = self.rollbacks = 0

    def folhas(self, desde):
        maior = {}
        for e, p, c, d in self.cal:
            if p >= desde and ((e, p) not in maior or c > maior[(e, p)][0]):
                maior[(e, p)] = (c, d)
        return [{"emp": e, "per": p.isoformat(), "codcal": c, "datpag": d.isoformat()} for (e, p), (c, d) in sorted(maior.items())]

    def liberacoes(self, desde):
        return [self._linha(k) for k in sorted(self.lib) if k[1] >= desde]

    def _linha(self, k):
        v = self.lib[k]
        return {"emp": k[0], "per": k[1].isoformat(), "sit": v["sit"], "ini": v["ini"].isoformat(),
                "usu": v["usu"], "gra": v["gra"].isoformat(), "obs": v["obs"]}

    def linha(self, emp, per):
        return self._linha((emp, per)) if (emp, per) in self.lib else None

    def data_pagamento(self, emp, per):
        cands = sorted([(c, d) for e, p, c, d in self.cal if e == emp and p == per], reverse=True)
        return cands[0][1] if cands else None

    def liberar(self, emp, per, ini, usu, obs):
        if self.falhar:
            raise RuntimeError("ORA-01031: insufficient privileges")
        self._backup()
        self.lib[(emp, per)] = {"sit": 1, "ini": ini, "usu": usu, "gra": HOJE, "obs": obs}

    def bloquear(self, emp, per, usu, obs):
        if (emp, per) not in self.lib:
            return 0
        self._backup()
        self.lib[(emp, per)].update(sit=0, usu=usu, gra=HOJE, obs=obs)
        return 1

    def _backup(self):
        if not hasattr(self, "_copia"):
            self._copia = {k: dict(v) for k, v in self.lib.items()}

    def commit(self):
        self.commits += 1
        self.__dict__.pop("_copia", None)

    def rollback(self):
        self.rollbacks += 1
        if hasattr(self, "_copia"):
            self.lib = self._copia
            del self._copia

    def fechar(self):
        pass


def pedir(acao, alvos=None, data_ini=None, obs=""):
    di = "null" if data_ini is None else f"'{data_ini}'"
    return psql(f"select central.lh_solicitar('{acao}', {j(alvos or [])}::jsonb, {di}, $o${obs}$o$);",
                papel="authenticated", sub=TI)


def rodar_fila(fila, sap):
    """Como o serviço: um pedido por vez até a fila esvaziar."""
    while True:
        peds = fila.proximo()
        if not peds:
            return
        for ped in peds:
            w.processar(fila, ped, abrir_sapiens=lambda: sap)


def status(pid):
    return psql(f"select status || '|' || coalesce(mensagem, '') from central.lh_pedidos where id = '{pid}';")


ok = True


def confere(nome, cond, detalhe=""):
    global ok
    print(("OK   " if cond else "FALHOU ") + nome + (f"  [{detalhe}]" if detalhe and not cond else ""))
    ok &= bool(cond)


def main():
    w.configurar_log()
    psql(f"""reset role;
      insert into auth.users values ('{TI}', 'ti@x') on conflict do nothing;
      insert into central.perfis(id, email, login, must_change_password) values ('{TI}', 'ti@x', 'ygor.adm', false) on conflict do nothing;
      insert into central.acessos_area select '{TI}', id from central.areas where slug = 'ti' on conflict do nothing;""",
         papel="postgres")
    fila, sap = FilaPg(), SapiensFalso()
    m1 = (HOJE.replace(day=1) - dt.timedelta(days=1)).replace(day=1)          # posição 1 do portal
    m2 = (m1 - dt.timedelta(days=1)).replace(day=1)
    velho = (w.inicio_janela(HOJE) - dt.timedelta(days=1)).replace(day=1)    # fora da janela
    pag3 = HOJE + dt.timedelta(days=5)
    sap.cal = [(3, m1, 511, pag3), (3, m1, 512, pag3), (5, m1, 513, HOJE + dt.timedelta(days=10)),
               (3, m2, 500, m1 + dt.timedelta(days=36)), (3, velho, 400, velho + dt.timedelta(days=36))]
    sap.lib[(3, m2)] = {"sit": 1, "ini": m1 + dt.timedelta(days=35), "usu": "VIRADA", "gra": HOJE, "obs": "Virada"}

    n = w.espelhar(sap, fila, HOJE)
    confere("leitura inicial: virada entra como fora do painel", n == 1, n)
    confere("folha fora da janela não vai para o painel",
            psql(f"select count(*) from central.lh_folhas where per_ref = '{velho}'") == "0")
    confere("CodCal mais recente", psql(f"select cod_cal from central.lh_folhas where num_emp=3 and per_ref='{m1}'") == "512")

    p1 = pedir("liberar", [{"emp": 3, "per": m1.isoformat()}], obs="RH pediu")
    p2 = pedir("agendar_padrao", [{"emp": 5, "per": m1.isoformat()}])
    rodar_fila(fila, sap)
    confere("liberar: aplicado", status(p1).startswith("aplicado"), status(p1))
    confere("liberar: Sapiens com SitLib 1 desde hoje", sap.lib[(3, m1)]["sit"] == 1 and sap.lib[(3, m1)]["ini"] == HOJE)
    confere("agendar padrão: DatPag - 1", sap.lib[(5, m1)]["ini"] == HOJE + dt.timedelta(days=9), sap.lib[(5, m1)]["ini"])
    confere("histórico: 2 ações pelo painel com o usuário",
            psql("select count(*) from central.lh_log where origem='painel' and usuario='ygor.adm'") == "2")
    confere("releitura não duplica histórico", psql("select count(*) from central.lh_log") == "3")

    p3 = pedir("bloquear", [{"emp": 3, "per": m1.isoformat()}, {"emp": 3, "per": m2.isoformat()}], obs="Recálculo")
    rodar_fila(fila, sap)
    confere("bloquear: aplicado", status(p3).startswith("aplicado"), status(p3))
    confere("bloquear: SitLib 0 nas duas (sem apagar linha)", sap.lib[(3, m1)]["sit"] == 0 and sap.lib[(3, m2)]["sit"] == 0)
    confere("espelho mostra bloqueado", psql(f"select sit_lib from central.lh_liberacoes where num_emp=3 and per_ref='{m1}'") == "0")

    p4 = pedir("bloquear", [{"emp": 3, "per": m1.isoformat()}], obs="de novo")
    rodar_fila(fila, sap)
    confere("bloquear o que já está bloqueado: sem histórico novo", psql("select count(*) from central.lh_log") == "5")

    sap.falhar = True
    antes = dict(sap.lib[(3, m1)])
    p5 = pedir("liberar", [{"emp": 3, "per": m1.isoformat()}])
    rodar_fila(fila, sap)
    sap.falhar = False
    confere("falha no Oracle: pedido em erro com mensagem amigável",
            status(p5) == "erro|Falha ao gravar no Sapiens. Detalhes no log do integrador (TECNOLIMP12).", status(p5))
    confere("falha no Oracle: rollback, nada mudou", sap.lib[(3, m1)] == antes and sap.rollbacks >= 1)

    sap.lib[(5, m1)]["sit"] = 0          # SQL de contingência direto no Oracle
    p6 = pedir("atualizar")
    rodar_fila(fila, sap)
    confere("atualizar: aplicado", status(p6).startswith("aplicado"), status(p6))
    confere("contingência aparece como fora do painel",
            psql(f"select count(*) from central.lh_log where origem='fora_do_painel' and num_emp=5") == "1")

    fila.manutencao()
    print("\nHistórico:")
    print(subprocess.run(["psql", "-U", "postgres", "-c",
                          "select usuario, num_emp, per_ref, acao, de, para, origem, obs from central.lh_log order by id"],
                         capture_output=True, text=True).stdout)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
