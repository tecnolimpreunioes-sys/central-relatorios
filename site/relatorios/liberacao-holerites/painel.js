// Liberação de holerites RH 24h — painel da T.I. na Central.
// Lê o espelho do Sapiens (central.lh_folhas / lh_liberacoes), a fila (lh_pedidos)
// e o histórico (lh_log). Cada clique vira um pedido (central.lh_solicitar); o
// integrador da TECNOLIMP12 grava na USU_TLIBHOL e devolve o resultado.
(function () {
  "use strict";

  // Empresas do RH 24h (nome pelo R030EMP) e os modelos que as atendem
  var EMPRESAS = [
    { emp: 1, nome: "Tecnolimp", modelos: "FPFF691–693" },
    { emp: 3, nome: "Pontual", modelos: "FPFF591–593" },
    { emp: 4, nome: "ServiPlus", modelos: "FPFF491–493" },
    { emp: 5, nome: "DRA", modelos: "FPFF891–893" },
    { emp: 6, nome: "Deltalimp", modelos: "FPFF791–793" },
    { emp: 7, nome: "Servinews", modelos: "FPFF491–493" }
  ];
  var POS = [
    { combo: "holerite", rot: "Atual no portal" },
    { combo: "holerite_anterior", rot: "Mês anterior" },
    { combo: "holerite_posterior", rot: "Há 2 meses" }
  ];
  var MESES = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"];
  var MESES_LONGOS = ["Janeiro", "Fevereiro", "Março", "Abril", "Maio", "Junho", "Julho", "Agosto", "Setembro", "Outubro", "Novembro", "Dezembro"];
  var LIMITE_SEM_RESPOSTA = 60000; // pedido pendente há mais de 1 min = integrador fora
  var INTERVALO = 1500;

  var HOJE = isoLocal(new Date());
  var PERFIL = null;
  var COMPS = [];
  var state = { folha: {}, lib: {}, log: [], pend: {}, pedidos: [], filtro: null, lido: null };

  /* ---------- utilidades ---------- */
  function $(id) { return document.getElementById(id); }
  function esc(v) { return TC.esc(v); }
  function k(emp, per) { return emp + "|" + per; }
  function isoLocal(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
  function addDias(iso, n) { var d = new Date(iso + "T12:00:00"); d.setDate(d.getDate() + n); return isoLocal(d); }
  function addMes(per, n) { var p = per.split("-").map(Number); var d = new Date(p[0], p[1] - 1 + n, 1); return isoLocal(d); }
  function br(iso) { if (!iso) return "—"; var p = iso.slice(0, 10).split("-"); return p[2] + "/" + p[1] + "/" + p[0]; }
  function curta(iso) { var p = iso.slice(0, 10).split("-"); return p[2] + "/" + p[1]; }
  function compNome(per) { var p = per.split("-"); return MESES[+p[1] - 1] + "/" + p[0]; }
  function compLongo(per) { var p = per.split("-"); return MESES_LONGOS[+p[1] - 1] + "/" + p[0]; }
  function nomeEmp(emp) { var e = EMPRESAS.find(function (x) { return x.emp === +emp; }); return e ? e.nome : "Empresa " + emp; }
  function dataHora(ts) { var d = new Date(ts); return br(isoLocal(d)) + " " + String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0"); }
  function show(id) { $(id).classList.remove("hidden"); }
  function hide(id) { $(id).classList.add("hidden"); }
  function esperar(ms) { return new Promise(function (ok) { setTimeout(ok, ms); }); }
  function toast(msg, tipo) { TC.toast(msg, tipo); }

  // janela do portal: 3 competências pelo calendário (posição 1 = mês passado) + a próxima, se já calculada
  function montarJanela() {
    var mesAtual = HOJE.slice(0, 8) + "01";
    COMPS = POS.map(function (p, i) {
      var per = addMes(mesAtual, -(i + 1));
      return { per: per, nome: compNome(per), rot: p.rot, combo: p.combo, pos: i + 1 };
    });
    var temProxima = Object.keys(state.folha).some(function (key) { return key.split("|")[1] === mesAtual; });
    if (temProxima) COMPS.unshift({ per: mesAtual, nome: compNome(mesAtual), rot: "Próxima (fora do portal)", combo: null, pos: 0 });
  }

  /* ---------- dados ---------- */
  function carregar() {
    return Promise.all([
      TC.db("lh_folhas?select=num_emp,per_ref,cod_cal,dat_pag,lido_em"),
      TC.db("lh_liberacoes?select=num_emp,per_ref,dat_ini,sit_lib,usu_lib,dat_gra,obs_lib"),
      TC.db("lh_pedidos?select=id,acao,alvos,status,criado_em,usuario_login&status=in.(pendente,processando)&order=criado_em"),
      TC.db("lh_log?select=em,usuario,num_emp,per_ref,acao,de,para,origem,obs&order=em.desc&limit=300")
    ]).then(function (r) {
      state.folha = {}; state.lib = {}; state.pend = {}; state.lido = null;
      r[0].forEach(function (f) {
        state.folha[k(f.num_emp, f.per_ref)] = { codcal: f.cod_cal, datpag: f.dat_pag };
        if (!state.lido || f.lido_em > state.lido) state.lido = f.lido_em;
      });
      r[1].forEach(function (l) {
        state.lib[k(l.num_emp, l.per_ref)] = { sit: l.sit_lib, ini: l.dat_ini, usu: l.usu_lib, gra: l.dat_gra, obs: l.obs_lib };
      });
      state.pedidos = r[2];
      r[2].forEach(function (p) {
        (p.alvos || []).forEach(function (a) { state.pend[k(a.emp, a.per)] = p; });
      });
      state.log = r[3];
      montarJanela();
      filtrosHist();
      render();
    });
  }

  function status(emp, per) {
    var key = k(emp, per);
    if (state.pend[key]) return { cls: "pend", txt: "Aplicando", det: "enviando ao Sapiens…" };
    var f = state.folha[key];
    if (!f) return { cls: "none", txt: "Sem folha", det: "não calculada" };
    var l = state.lib[key];
    if (!l || l.sit === 0) return { cls: "lock", txt: "Bloqueado", det: l ? (l.obs || "bloqueado pela TI") : "pagamento " + curta(f.datpag) };
    if (l.ini > HOJE) return { cls: "sched", txt: "Agendado", det: "a partir de " + curta(l.ini) };
    return { cls: "ok", txt: "Liberado", det: "desde " + curta(l.ini) };
  }

  /* ---------- render ---------- */
  function render() {
    $("hoje").textContent = br(HOJE);
    $("lastSync").textContent = state.lido ? dataHora(state.lido) : "ainda não lidas";
    renderOverview(); renderGrid(); renderHist(); renderBanner();
  }

  // tooltips (data-tip): explicam cada situação onde ela aparece
  var TIP = {
    ok: "Liberado: o colaborador já vê o holerite no portal RH 24h.",
    sched: "Agendado: aparece no portal a partir da data marcada. Até lá o colaborador vê “🔒 Em breve”.",
    lock: "Bloqueado: o colaborador vê “🔒 Em breve”. Toda folha nova nasce assim até a TI liberar.",
    none: "Sem folha: a folha mensal desta empresa ainda não foi calculada no Sapiens (R044CAL). Não há o que liberar.",
    pend: "Aplicando: o pedido está na fila do integrador, que grava no Sapiens em segundos.",
    fora: "Fora do painel: alteração feita direto no Sapiens (SQL de contingência ou virada), sem passar por aqui. O painel detecta na leitura do Sapiens e registra.",
    painel: "Feita por este painel, pelo usuário da linha.",
    proxima: "Folha do mês corrente já calculada. Ainda não aparece no portal; dá para agendar antes."
  };

  var LEG = [
    { cls: "ok", txt: "Liberado", d: "aparece no portal" },
    { cls: "sched", txt: "Agendado", d: "sai na data marcada" },
    { cls: "lock", txt: "Bloqueado", d: "padrão: “Em breve”" },
    { cls: "none", txt: "Sem folha", d: "mês não calculado" }
  ];
  function renderOverview() {
    var atual = COMPS.find(function (c) { return c.pos === 1; }).per;
    var n = { ok: 0, sched: 0, lock: 0, pend: 0, none: 0 };
    EMPRESAS.forEach(function (e) { n[status(e.emp, atual).cls]++; });
    var com = EMPRESAS.length - n.none;
    var prox = EMPRESAS.map(function (e) { return state.lib[k(e.emp, atual)]; })
      .filter(function (l) { return l && l.sit === 1 && l.ini > HOJE; }).map(function (l) { return l.ini; }).sort()[0];
    var det = { ok: "de " + com + " com folha", sched: prox ? "próxima em " + curta(prox) : "nenhuma na fila" };
    $("overview").innerHTML =
      '<div class="ov-head"><div><span class="ov-t">' + compLongo(atual) + '</span><span class="ov-s">mês atual no portal · clique num status para destacá-lo na grade</span></div>' +
      '<div class="ov-pct"><b>' + (com ? Math.round(n.ok / com * 100) : 0) + "%</b>liberado</div></div>" +
      '<div class="bar" role="img" aria-label="' + n.ok + " liberadas, " + n.sched + " agendadas, " + n.lock + " bloqueadas, " + n.none + ' sem folha">' +
      ["ok", "sched", "pend", "lock", "none"].map(function (c) { return '<i class="' + c + '" style="flex-grow:' + n[c] + '"></i>'; }).join("") + "</div>" +
      '<div class="ov-legend">' + LEG.map(function (x) {
        return '<button class="lg ' + x.cls + '" data-filtro="' + x.cls + '" data-tip="' + esc(TIP[x.cls]) + '" aria-pressed="' + (state.filtro === x.cls) + '">' +
          '<span class="n">' + n[x.cls] + '</span><span class="d"><b>' + x.txt + "</b>" + (det[x.cls] || x.d) + "</span></button>";
      }).join("") + "</div>";
  }

  function renderGrid() {
    var h = "<thead><tr><th>Empresa</th>" + COMPS.map(function (c) {
      return '<th class="comp ' + (c.pos === 1 ? "cur" : "") + '"><div class="ch"><div><span class="cname">' + c.nome + '</span><span class="cpos">' +
        (c.pos === 1 ? '<span class="tag">atual</span>' : "") + (c.pos === 0 ? '<span data-tip="' + esc(TIP.proxima) + '">' + c.rot + " ⓘ</span>" : c.rot) + "</span></div>" +
        '<button class="bulk" data-bulk="' + c.per + '" title="Aplicar a mesma ação a todas as empresas" aria-label="Todas as empresas em ' + c.nome + '">Todas ▾</button></div></th>';
    }).join("") + "</tr></thead><tbody>";
    EMPRESAS.forEach(function (e) {
      h += '<tr><td class="emp"><b>' + esc(e.nome) + "</b><small>empresa " + e.emp + " · " + e.modelos + "</small></td>";
      COMPS.forEach(function (c) {
        var s = status(e.emp, c.per);
        var dim = state.filtro && s.cls !== state.filtro ? "dim" : "";
        h += '<td><button class="cell ' + dim + '" data-tip="' + esc(TIP[s.cls]) + '" data-emp="' + e.emp + '" data-per="' + c.per + '" ' + (s.cls === "none" || s.cls === "pend" ? "disabled" : "") +
          ' aria-label="' + esc(e.nome) + ", " + c.nome + ": " + s.txt + '"><span class="chip ' + s.cls + '">' + s.txt + "</span><small>" + esc(s.det) + "</small></button></td>";
      });
      h += "</tr>";
    });
    $("grid").innerHTML = h + "</tbody>";
  }

  function renderHist() {
    var fe = $("fEmp").value, fc = $("fComp").value, ft = $("fTxt").value.toLowerCase();
    var rows = state.log.filter(function (r) {
      return (!fe || r.num_emp == fe) && (!fc || r.per_ref === fc) && (!ft || (r.usuario + " " + r.obs).toLowerCase().indexOf(ft) !== -1);
    });
    var visto = {};
    $("hist").innerHTML = "<thead><tr><th>Data/hora</th><th>Usuário</th><th>Empresa</th><th>Competência</th><th>Ação</th><th>De → Para</th><th>Origem</th><th>Observação</th><th></th></tr></thead><tbody>" +
      (rows.length ? rows.map(function (r) {
        // só a linha mais recente de uma liberação que ainda vale ganha "Reverter"
        var key = k(r.num_emp, r.per_ref), primeira = !visto[key]; visto[key] = 1;
        var st = status(r.num_emp, r.per_ref).cls;
        var rev = primeira && (r.acao === "Liberado" || r.acao === "Agendado") && (st === "ok" || st === "sched") &&
          COMPS.some(function (c) { return c.per === r.per_ref; });
        return '<tr><td style="white-space:nowrap">' + dataHora(r.em) + "</td><td>" + esc(r.usuario) + "</td><td>" + esc(nomeEmp(r.num_emp)) + "</td><td>" + compNome(r.per_ref) +
          "</td><td><b>" + esc(r.acao) + "</b></td><td>" + esc(r.de) + " → " + esc(r.para) + '</td><td><span class="orig ' + (r.origem === "fora_do_painel" ? "sql" : "") +
          '" data-tip="' + esc(r.origem === "fora_do_painel" ? TIP.fora : TIP.painel) + '">' +
          (r.origem === "fora_do_painel" ? "fora do painel" : "painel") + "</span></td><td>" + esc(r.obs) + "</td><td>" +
          (rev ? '<button class="btn sm" data-reverter="' + key + '" data-tip="Abre a célula com “Reverter liberação” marcado: volta a “🔒 Em breve” no portal.">↩ Reverter</button>' : "") + "</td></tr>";
      }).join("") : '<tr><td colspan="9" style="text-align:center;color:var(--color-subtle);padding:24px">Nenhum registro com esses filtros.</td></tr>') + "</tbody>";
  }

  function filtrosHist() {
    var fe = $("fEmp"), fc = $("fComp"), ve = fe.value, vc = fc.value;
    fe.innerHTML = '<option value="">Todas as empresas</option>' + EMPRESAS.map(function (e) { return '<option value="' + e.emp + '">' + esc(e.nome) + "</option>"; }).join("");
    var pers = COMPS.map(function (c) { return c.per; }).concat(state.log.map(function (r) { return r.per_ref; }))
      .filter(function (v, i, a) { return a.indexOf(v) === i; }).sort().reverse();
    fc.innerHTML = '<option value="">Todas as competências</option>' + pers.map(function (p) { return '<option value="' + p + '">' + compNome(p) + "</option>"; }).join("");
    fe.value = ve; fc.value = vc;
  }

  function renderBanner() {
    var agora = Date.now();
    var atrasados = state.pedidos.filter(function (p) { return p.status === "pendente" && agora - new Date(p.criado_em).getTime() > LIMITE_SEM_RESPOSTA; });
    $("bannerWorker").classList.toggle("hidden", atrasados.length === 0);
    $("pendCount").textContent = atrasados.length;
  }

  /* ---------- gaveta de uma célula ---------- */
  var cur = null;
  function openDrawer(emp, per, acaoInicial) {
    cur = { emp: +emp, per: per };
    var key = k(emp, per), f = state.folha[key], l = state.lib[key], s = status(emp, per);
    var e = EMPRESAS.find(function (x) { return x.emp === +emp; }), c = COMPS.find(function (x) { return x.per === per; });
    var padrao = addDias(f.datpag, -1);
    var liberado = s.cls === "ok" || s.cls === "sched";
    $("dTitle").textContent = e.nome + " · " + c.nome;
    $("dSub").innerHTML = '<span class="chip ' + s.cls + '">' + s.txt + "</span> " + esc(s.det);
    var hist = state.log.filter(function (r) { return r.num_emp == emp && r.per_ref === per; }).slice(0, 4);
    var portal = COMPS.filter(function (x) { return x.pos > 0; });
    $("dBody").innerHTML =
      "<dl><dt>Empresa</dt><dd>" + esc(e.nome) + " (" + e.emp + ") · modelos " + e.modelos + "</dd>" +
      "<dt>No portal</dt><dd>" + (c.combo ? c.rot + " (combo " + c.combo + ")" : "ainda fora do portal") + "</dd>" +
      "<dt>Cálculo</dt><dd>CodCal " + f.codcal + " · folha mensal</dd>" +
      "<dt>Pagamento</dt><dd>" + br(f.datpag) + "</dd>" +
      "<dt>Liberação</dt><dd>" + (l ? (l.sit ? "a partir de " + br(l.ini) : "bloqueado") : "nunca liberado") + "</dd>" +
      "<dt>Último registro</dt><dd>" + (l ? esc(l.usu) + " em " + br(l.gra) : "—") + "</dd></dl>" +
      '<div class="sec">O que fazer</div>' +
      '<label class="opt"><input type="radio" name="acao" value="agora" ' + (s.cls !== "ok" ? "checked" : "") + "><span><b>Liberar agora</b><small>Aparece no portal assim que o Sapiens receber (segundos).</small></span></label>" +
      '<label class="opt"><input type="radio" name="acao" value="padrao"><span><b>No padrão</b><small>Pagamento − 1 dia: a partir de ' + br(padrao) +
        (padrao <= HOJE ? " (já passou: libera na hora)" : "") + ".</small></span></label>" +
      '<label class="opt"><input type="radio" name="acao" value="agendar" ' + (s.cls === "sched" ? "checked" : "") + "><span><b>Agendar em outra data</b><small>Ex.: “RH pediu para soltar dia 04”.</small><br>" +
      '<input type="date" id="dData" value="' + (l && l.sit && l.ini > HOJE ? l.ini : (padrao > HOJE ? padrao : addDias(HOJE, 1))) + '" min="' + addDias(HOJE, 1) + '"></span></label>' +
      '<label class="opt' + (liberado ? " rev" : "") + '"><input type="radio" name="acao" value="bloquear" ' + (s.cls === "ok" ? "checked" : "") + "><span><b>" +
        (liberado ? "↩ Reverter liberação" : "Bloquear") + "</b><small>" +
        (liberado ? "Desfaz a liberação: volta a “🔒 Em breve” no portal na próxima consulta. Fica no histórico." : "Mantém “🔒 Em breve” e registra o motivo. Use em recálculo ou erro.") +
        "</small></span></label>" +
      '<label class="f" for="dObs">Observação (quem pediu / motivo)</label>' +
      '<input class="t" id="dObs" maxlength="60" placeholder="Ex.: RH (Dayane) pediu para soltar dia 04">' +
      '<div class="hint">Até 60 caracteres. Obrigatória para bloquear ou reverter.</div>' +
      '<div class="sec">Como o colaborador vê hoje</div>' +
      '<div class="pv"><div class="pv-h">Portal RH 24h · Holerite</div>' +
      portal.map(function (x) {
        var v = status(emp, x.per).cls === "ok";
        return '<div class="pv-r ' + (x.per === per ? "sel" : "") + '"><span>' + compLongo(x.per) + "</span>" + (v ? "<span>📄 Ver holerite</span>" : '<span class="soon">🔒 Em breve</span>') + "</div>";
      }).join("") + "</div>" +
      '<div class="hint">Agendado ou bloqueado aparece igual: “Em breve”, sem data.</div>' +
      '<div class="sec">Últimos registros</div><ul class="mini">' +
      (hist.length ? hist.map(function (r) { return "<li>" + dataHora(r.em) + " · <b>" + esc(r.acao) + "</b> por " + esc(r.usuario) + (r.obs ? " — " + esc(r.obs) : "") + "</li>"; }).join("") : "<li>Nenhum registro.</li>") + "</ul>";
    show("overlay"); show("drawer");
    if (acaoInicial) {
      document.querySelector("input[name=acao][value=" + acaoInicial + "]").checked = true;
      $("dObs").placeholder = "Motivo da reversão (obrigatório)";
      $("dObs").focus();
    } else document.querySelector("#drawer .x").focus();
  }
  function closeDrawer() { hide("overlay"); hide("drawer"); cur = null; }

  $("dApply").addEventListener("click", function () {
    var sel = document.querySelector("input[name=acao]:checked");
    var acao = sel && sel.value;
    var obs = $("dObs").value.trim();
    if (!acao) return toast("Escolha uma ação.", "err");
    if (acao === "bloquear" && !obs) { $("dObs").focus(); return toast("Informe o motivo (obrigatório para bloquear ou reverter).", "err"); }
    var ini = acao === "agendar" ? $("dData").value : null;
    if (acao === "agendar" && (!ini || ini <= HOJE)) return toast("A data do agendamento precisa ser depois de hoje.", "err");
    var alvo = [{ emp: cur.emp, per: cur.per }];
    confirmar(acao, ini, obs, alvo, function () { closeDrawer(); enviar(acao, ini, obs, alvo); });
  });

  /* ---------- lote por competência ---------- */
  function openBulk(per) {
    var c = COMPS.find(function (x) { return x.per === per; });
    var alvos = EMPRESAS.filter(function (e) { return state.folha[k(e.emp, per)] && !state.pend[k(e.emp, per)]; }).map(function (e) { return { emp: e.emp, per: per }; });
    if (!alvos.length) return toast("Nenhuma empresa com folha calculada em " + c.nome + ".", "err");
    modal("Todas as empresas · " + c.nome,
      '<p class="hint" style="margin-top:0">Aplica a mesma ação às ' + alvos.length + " empresas com folha calculada em " + c.nome + " (empresa sem folha é ignorada).</p>" +
      '<label class="opt"><input type="radio" name="bacao" value="padrao" checked><span><b>No padrão</b><small>Pagamento − 1 dia, por empresa: cada uma libera 1 dia antes do próprio pagamento.</small></span></label>' +
      '<label class="opt"><input type="radio" name="bacao" value="agendar"><span><b>Agendar na mesma data</b><small>Ex.: “solta dia 04”.</small><br><input type="date" id="bData" min="' + addDias(HOJE, 1) + '" value="' + addDias(HOJE, 1) + '"></span></label>' +
      '<label class="opt"><input type="radio" name="bacao" value="agora"><span><b>Liberar todas agora</b></span></label>' +
      '<label class="opt"><input type="radio" name="bacao" value="bloquear"><span><b>Bloquear / reverter todas</b><small>Todas voltam a “🔒 Em breve” no portal.</small></span></label>' +
      '<label class="f" for="bObs">Observação</label><input class="t" id="bObs" maxlength="60" placeholder="Quem pediu / motivo">',
      [["Cancelar", "btn", closeModal], ["Continuar", "btn primary", function () {
        var a = document.querySelector("input[name=bacao]:checked").value, obs = $("bObs").value.trim();
        if (a === "bloquear" && !obs) return toast("Informe o motivo do bloqueio.", "err");
        var d = $("bData").value;
        if (a === "agendar" && (!d || d <= HOJE)) return toast("A data precisa ser depois de hoje.", "err");
        var ini = a === "agendar" ? d : null;
        // bloqueio feito de propósito pela TI (ex.: recálculo) não é desfeito pelo lote; libera-se pela célula
        var lista = a === "bloquear" ? alvos : alvos.filter(function (x) { var l = state.lib[k(x.emp, x.per)]; return !(l && l.sit === 0); });
        var pulou = alvos.length - lista.length;
        if (!lista.length) return toast("Todas as empresas estão bloqueadas pela TI — libere pela célula.", "err");
        confirmar(a, ini, obs, lista, function () { enviar(a, ini, obs, lista); },
          pulou ? pulou + " empresa(s) bloqueada(s) pela TI ficam de fora — libere pela própria célula." : "");
      }]]);
  }

  /* ---------- confirmação e envio ---------- */
  function descreve(acao, ini) {
    if (acao === "agora") return "Liberar agora";
    if (acao === "bloquear") return "Bloquear / reverter liberação";
    if (acao === "padrao") return "No padrão (pagamento − 1 dia)";
    if (acao === "atualizar") return "Atualizar do Sapiens";
    return "Agendar para " + br(ini);
  }
  function confirmar(acao, ini, obs, alvos, ok, aviso) {
    var lista = alvos.map(function (a) {
      var f = state.folha[k(a.emp, a.per)];
      var dp = addDias(f.datpag, -1);
      var d = acao === "padrao" ? " → a partir de " + br(dp) + (dp <= HOJE ? " (já passou: libera na hora)" : "") : "";
      return "<li>" + esc(nomeEmp(a.emp)) + " · " + compNome(a.per) + d + "</li>";
    }).join("");
    modal("Confirmar", '<p style="margin-top:0"><b>' + descreve(acao, ini) + '</b></p><ul class="summary">' + lista + "</ul>" +
      (aviso ? '<p class="hint" style="color:var(--lock)">⚠ ' + esc(aviso) + "</p>" : "") +
      (obs ? '<p class="hint">Obs.: ' + esc(obs) + "</p>" : "") +
      '<p class="hint">Fica registrado no histórico como <b>' + esc(PERFIL.login) + "</b>.</p>",
      [["Voltar", "btn", closeModal], ["Confirmar", acao === "bloquear" ? "btn danger" : "btn primary", function () { closeModal(); ok(); }]]);
  }

  var ACAO_RPC = { agora: "liberar", agendar: "agendar", padrao: "agendar_padrao", bloquear: "bloquear", atualizar: "atualizar" };

  function enviar(acao, ini, obs, alvos) {
    var atualizar = acao === "atualizar";
    var quem = atualizar ? "O integrador relê as folhas e as liberações."
      : alvos.length === 1 ? nomeEmp(alvos[0].emp) + " · " + compNome(alvos[0].per) : alvos.length + " empresas · " + compNome(alvos[0].per);
    loader.open(atualizar ? "Atualizando do Sapiens" : descreve(acao, ini), quem,
      ["Pedido registrado no painel", atualizar ? "Integrador lendo o Sapiens" : "Gravando na USU_TLIBHOL (Sapiens)", "Painel atualizado"]);
    TC.rpc("lh_solicitar", { p_acao: ACAO_RPC[acao], p_alvos: alvos || [], p_data_ini: ini, p_obs: obs || "" })
      .then(function (id) {
        loader.pedido = id; $("ldCancel").disabled = false;
        loader.go(1);
        return carregar().then(function () { return acompanhar(id, atualizar); });
      })
      .catch(function (err) {
        loader.warn("Pedido não registrado", err.message || "Erro ao registrar o pedido.");
      });
  }

  // acompanha o pedido até o integrador responder
  function acompanhar(id, atualizar) {
    var inicio = Date.now();
    function consultar() {
      return TC.db("lh_pedidos?id=eq." + id + "&select=status,mensagem").then(function (r) {
        var p = r && r[0];
        if (!p) throw new Error("Pedido não encontrado.");
        if (p.status === "aplicado") {
          loader.go(2);
          return carregar().then(function () {
            loader.ok(atualizar ? "Painel atualizado" : "Aplicado no Sapiens", atualizar ? "Folhas e liberações relidas." : "Já vale no portal RH 24h.");
          });
        }
        if (p.status === "cancelado") return null; // quem cancelou já mostrou o resultado
        if (p.status === "erro") {
          return carregar().then(function () { loader.warn("Não aplicado", p.mensagem || "O integrador recusou o pedido."); });
        }
        if (p.status === "processando") loader.go(1);
        if (p.status === "pendente" && Date.now() - inicio > LIMITE_SEM_RESPOSTA) {
          renderBanner();
          loader.warn("Integrador sem resposta", "O pedido ficou na fila e entra assim que ele voltar. Urgente? Use o SQL de contingência.");
          return null;
        }
        if (!loader.ativo || loader.pedido !== id) return null; // fechou ou cancelou: a grade se atualiza na próxima leitura
        return esperar(INTERVALO).then(consultar);
      });
    }
    return esperar(INTERVALO).then(consultar).catch(function (err) {
      loader.warn("Não foi possível acompanhar o pedido", err.message || "");
    });
  }

  /* ---------- carregamento: etapas reais do pedido, check no fim ---------- */
  var loader = {
    ativo: false, timers: [], n: 3, pedido: null,
    open: function (tit, sub, etapas) {
      this.timers.forEach(clearTimeout); this.timers = [];
      this.ativo = true; this.n = etapas.length;
      var w = $("ldWrap");
      w.classList.remove("out", "hidden");
      $("ld").className = "ld";
      $("ldTit").textContent = tit;
      $("ldSub").textContent = sub;
      $("ldSteps").innerHTML = etapas.map(function (e) { return '<li><span class="ic"></span>' + esc(e) + "</li>"; }).join("");
      this.pedido = null;
      $("ldCancel").disabled = true; // libera quando o pedido existir
      show("ldCancel"); hide("ldOk"); show("ldActs");
      this.go(0);
    },
    go: function (i) {
      if (!this.ativo) return;
      document.querySelectorAll("#ldSteps li").forEach(function (li, j) { li.className = j < i ? "done" : j === i ? "run" : ""; });
      document.querySelector("#ldBar i").style.width = Math.min(100, (i + 0.5) / this.n * 100) + "%";
    },
    ok: function (tit, sub) {
      if (!this.ativo) return;
      this.go(this.n);
      $("ld").classList.add("ok");
      hide("ldActs");
      $("ldTit").textContent = tit;
      $("ldSub").textContent = sub;
      var self = this;
      this.timers.push(setTimeout(function () { self.close(); }, 1300));
    },
    warn: function (tit, sub) {
      if (!this.ativo) return;
      var run = document.querySelector("#ldSteps li.run");
      if (run) run.classList.replace("run", "wait");
      $("ld").classList.add("warn");
      $("ldTit").textContent = tit;
      $("ldSub").textContent = sub;
      show("ldActs"); show("ldOk"); $("ldOk").focus();
    },
    close: function () {
      this.ativo = false; this.timers.forEach(clearTimeout); this.timers = [];
      var w = $("ldWrap"); w.classList.add("out");
      var self = this;
      setTimeout(function () { if (!self.ativo) w.classList.add("hidden"); }, 350);
    }
  };
  $("ldOk").addEventListener("click", function () { loader.close(); });

  // cancelar: só tira da fila o que o integrador ainda não pegou
  $("ldCancel").addEventListener("click", function () {
    var id = loader.pedido;
    if (!id) return;
    $("ldCancel").disabled = true;
    TC.rpc("lh_cancelar", { p_id: id }).then(function (st) {
      loader.pedido = null;
      return carregar().then(function () {
        hide("ldCancel");
        if (st === "cancelado") return loader.warn("Pedido cancelado", "Saiu da fila antes de chegar ao Sapiens. Nada foi alterado.");
        if (st === "aplicado") return loader.warn("Já tinha sido aplicado", "Para desfazer, abra a célula e use “Reverter liberação” (ou libere de novo).");
        loader.warn("Não deu para cancelar", "O integrador já está gravando no Sapiens. Quando terminar, desfaça pela própria célula.");
      });
    }).catch(function (err) {
      $("ldCancel").disabled = false;
      toast(err.message || "Erro ao cancelar.", "err");
    });
  });

  /* ---------- modal, navegação ---------- */
  function modal(title, body, buttons) {
    $("mTitle").textContent = title;
    $("mBody").innerHTML = body;
    var foot = $("mFoot"); foot.innerHTML = "";
    buttons.forEach(function (b) { var el = document.createElement("button"); el.className = b[1]; el.textContent = b[0]; el.onclick = b[2]; foot.appendChild(el); });
    show("mOverlay"); show("modal"); foot.lastChild.focus();
  }
  function closeModal() { hide("mOverlay"); hide("modal"); }

  function setTab(name) {
    document.querySelectorAll(".tab").forEach(function (t) { t.setAttribute("aria-selected", t.dataset.tab === name); });
    [["tabPainel", "painel"], ["tabHistorico", "historico"], ["tabComo", "como"]].forEach(function (p) { $(p[0]).classList.toggle("hidden", p[1] !== name); });
  }
  function route() {
    var h = location.hash.replace("#", "") || "painel";
    setTab(["painel", "historico", "como"].indexOf(h) !== -1 ? h : "painel");
  }

  function ligarTooltips() {
    var tip = document.createElement("div");
    tip.className = "tip hidden"; tip.setAttribute("role", "tooltip"); tip.id = "tip";
    document.body.appendChild(tip);
    function mostrar(el) {
      tip.textContent = el.dataset.tip; show("tip");
      var r = el.getBoundingClientRect(), w = tip.offsetWidth, h = tip.offsetHeight;
      var x = Math.max(8, Math.min(window.innerWidth - w - 8, r.left + r.width / 2 - w / 2));
      var y = r.top - h - 8 < 8 ? r.bottom + 8 : r.top - h - 8;
      tip.style.left = x + "px"; tip.style.top = y + "px";
    }
    function sair() { hide("tip"); }
    ["mouseover", "focusin"].forEach(function (ev) {
      document.addEventListener(ev, function (e) { var el = e.target.closest && e.target.closest("[data-tip]"); el ? mostrar(el) : sair(); });
    });
    ["focusout", "scroll"].forEach(function (ev) { document.addEventListener(ev, sair, true); });
  }

  function ligarEventos() {
    ligarTooltips();
    document.addEventListener("click", function (e) {
      var cell = e.target.closest(".cell"); if (cell && !cell.disabled) return openDrawer(cell.dataset.emp, cell.dataset.per);
      var rev = e.target.closest("[data-reverter]");
      if (rev) { var a = rev.dataset.reverter.split("|"); return openDrawer(a[0], a[1], "bloquear"); }
      var bulk = e.target.closest("[data-bulk]"); if (bulk) return openBulk(bulk.dataset.bulk);
      var lg = e.target.closest("[data-filtro]");
      if (lg) { state.filtro = state.filtro === lg.dataset.filtro ? null : lg.dataset.filtro; renderOverview(); renderGrid(); return; }
      if (e.target.closest("[data-close]") || e.target.id === "overlay") return closeDrawer();
      if (e.target.id === "mOverlay") return closeModal();
      var tab = e.target.closest(".tab"); if (tab) { location.hash = tab.dataset.tab; return; }
    });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") { closeModal(); closeDrawer(); } });
    ["fEmp", "fComp", "fTxt"].forEach(function (id) { $(id).addEventListener("input", renderHist); });
    $("btnSync").addEventListener("click", function () { enviar("atualizar", null, "", []); });
    $("btnPrint").addEventListener("click", function () { window.print(); });
    window.addEventListener("hashchange", route);
    // a fila pode mudar por outro usuário ou pelo integrador: relê ao voltar para a aba
    document.addEventListener("visibilitychange", function () { if (!document.hidden && !loader.ativo) carregar().catch(function () {}); });
  }

  function semAcesso(msg) {
    $("viewReport").innerHTML = '<div class="vazio" style="margin-top:20px"><b>' + esc(msg) + "</b>Peça acesso ao administrador da Central (área T.I. ou o relatório “Liberação de Holerites”).</div>";
  }

  /* ---------- início ---------- */
  TC.exigirLogin().then(function (p) {
    PERFIL = p;
    TC.montarMenuUsuario($("user-slot"), p);
    return TC.rpc("lh_pode").then(function (pode) {
      if (!pode) return semAcesso("Sem acesso à Liberação de Holerites.");
      ligarEventos(); route();
      return carregar();
    });
  }).catch(function (err) {
    toast(err.message || "Erro ao carregar o painel.", "err");
  });
})();
