// Central de Relatórios Tecnolimp — sessão, acesso ao Supabase e proteção de páginas.
// Login único: a sessão fica no navegador (localStorage) e vale para a Central
// e para todos os relatórios publicados dentro dela (mesmo endereço).
(function (global) {
  "use strict";
  var CFG = global.CENTRAL_CONFIG;
  var CHAVE = "tl_central_sessao";
  var ROOT = (function () {
    var s = document.currentScript && document.currentScript.src;
    return s ? s.replace(/assets\/auth\.js(\?.*)?$/, "") : "/";
  })();

  // ---------- armazenamento ----------
  function ler() {
    try { var r = localStorage.getItem(CHAVE); return r ? JSON.parse(r) : null; } catch (e) { return null; }
  }
  function gravar(s) { try { localStorage.setItem(CHAVE, JSON.stringify(s)); } catch (e) {} }
  function limpar() { try { localStorage.removeItem(CHAVE); } catch (e) {} }

  function guardarToken(body) {
    var s = {
      access_token: body.access_token,
      refresh_token: body.refresh_token,
      expires_at: body.expires_at || Math.floor(Date.now() / 1000) + (body.expires_in || 3600),
      user: { id: body.user && body.user.id, email: body.user && body.user.email }
    };
    gravar(s);
    return s;
  }

  function authPost(path, payload, token) {
    return fetch(CFG.SB_URL + "/auth/v1/" + path, {
      method: "POST",
      headers: { apikey: CFG.SB_KEY, Authorization: "Bearer " + (token || CFG.SB_KEY), "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (b) { return { ok: r.ok, status: r.status, body: b }; });
    });
  }

  // renova o token se faltar menos de 2 min para expirar (uma renovação por vez)
  var renovando = null;
  function sessaoValida() {
    var s = ler();
    if (!s || !s.refresh_token) return Promise.resolve(null);
    if (s.expires_at - 120 > Date.now() / 1000) return Promise.resolve(s);
    if (renovando) return renovando;
    renovando = authPost("token?grant_type=refresh_token", { refresh_token: s.refresh_token }).then(function (res) {
      renovando = null;
      if (!res.ok) { limpar(); return null; }
      return guardarToken(res.body);
    }, function () { renovando = null; return s; });
    return renovando;
  }

  // ---------- REST ----------
  function chamar(url, opts, schema) {
    opts = opts || {};
    return sessaoValida().then(function (s) {
      var h = { apikey: CFG.SB_KEY, Authorization: "Bearer " + (s ? s.access_token : CFG.SB_KEY), "Content-Type": "application/json" };
      if (schema && schema !== "public") {
        h[(opts.method || "GET") === "GET" ? "Accept-Profile" : "Content-Profile"] = schema;
      }
      if (opts.prefer) h.Prefer = opts.prefer;
      return fetch(url, { method: opts.method || "GET", headers: h, body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined });
    }).then(function (r) {
      if (r.status === 401) { limpar(); irLogin(); throw new Error("Sessão expirada"); }
      if (!r.ok) {
        return r.json().catch(function () { return {}; }).then(function (j) {
          var e = new Error(j.message || j.error || j.msg || r.statusText || "Erro"); e.status = r.status; throw e;
        });
      }
      return r.status === 204 ? null : r.text().then(function (t) { return t ? JSON.parse(t) : null; });
    });
  }
  function rest(path, opts) { return chamar(CFG.SB_URL + "/rest/v1/" + path, opts, (opts && opts.schema) || "public"); }
  function db(path, opts) { opts = opts || {}; opts.schema = CFG.SB_SCHEMA; return rest(path, opts); }
  function rpc(nome, args, schema) {
    return chamar(CFG.SB_URL + "/rest/v1/rpc/" + nome, { method: "POST", body: args || {} }, schema || CFG.SB_SCHEMA);
  }
  function fn(nome, body) {
    return sessaoValida().then(function (s) {
      return fetch(CFG.SB_URL + "/functions/v1/" + nome, {
        method: "POST",
        headers: { apikey: CFG.SB_KEY, Authorization: "Bearer " + (s ? s.access_token : ""), "Content-Type": "application/json" },
        body: JSON.stringify(body || {})
      });
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (b) {
        if (!r.ok) throw new Error(b.error || b.message || "Erro ao processar a solicitação");
        return b;
      });
    });
  }

  // ---------- login / perfil ----------
  function login(email, senha) {
    return authPost("token?grant_type=password", { email: String(email).trim().toLowerCase(), password: senha }).then(function (res) {
      if (!res.ok) {
        var m = (res.body && (res.body.error_description || res.body.msg)) || "";
        throw new Error(/invalid/i.test(m) ? "E-mail ou senha incorretos." : (m || "Não foi possível entrar."));
      }
      guardarToken(res.body);
      return perfil(true).then(function (p) {
        if (!p) { limpar(); throw new Error("Seu usuário não está liberado na Central. Fale com o administrador."); }
        if (!p.ativo) { limpar(); throw new Error("Seu acesso está desativado. Fale com o administrador."); }
        rpc("registrar_acesso").catch(function () {});
        return p;
      });
    });
  }

  var cachePerfil = null;
  function perfil(forcar) {
    if (cachePerfil && !forcar) return Promise.resolve(cachePerfil);
    var s = ler();
    if (!s) return Promise.resolve(null);
    return db("perfis?select=id,email,nome,is_admin,must_change_password,ativo&id=eq." + s.user.id).then(function (rows) {
      cachePerfil = rows && rows[0] ? rows[0] : null;
      return cachePerfil;
    });
  }

  function trocarSenha(nova) {
    return sessaoValida().then(function (s) {
      if (!s) throw new Error("Sessão expirada");
      return fetch(CFG.SB_URL + "/auth/v1/user", {
        method: "PUT",
        headers: { apikey: CFG.SB_KEY, Authorization: "Bearer " + s.access_token, "Content-Type": "application/json" },
        body: JSON.stringify({ password: nova })
      });
    }).then(function (r) {
      return r.json().catch(function () { return {}; }).then(function (b) {
        if (!r.ok) {
          var m = b.msg || b.message || b.error_description || "";
          if (/different|same/i.test(m)) throw new Error("A nova senha precisa ser diferente da atual.");
          if (/weak|short|characters/i.test(m)) throw new Error("Senha fraca: use pelo menos 8 caracteres com letras e números.");
          throw new Error(m || "Não foi possível alterar a senha.");
        }
        return rpc("concluir_troca_senha");
      });
    }).then(function () { cachePerfil = null; });
  }

  function sair() {
    var s = ler();
    limpar(); cachePerfil = null;
    if (s) authPost("logout", {}, s.access_token).catch(function () {});
    location.href = ROOT + "index.html";
  }

  function caminhoAtual() {
    var atual = location.href;
    return atual.indexOf(ROOT) === 0 ? atual.slice(ROOT.length) : "index.html";
  }
  function irLogin(destino) {
    location.href = ROOT + "login.html?next=" + encodeURIComponent(destino || caminhoAtual());
  }
  function destinoSeguro(next) {
    // só aceita caminhos internos da Central (evita redirecionamento para fora)
    if (!next || /^[a-z]+:|^\/\/|\\/i.test(next) || next.indexOf("..") !== -1) return "index.html";
    return next;
  }

  // Protege a página. opts: { admin, permitirTrocaPendente }
  function exigirLogin(opts) {
    opts = opts || {};
    return sessaoValida().then(function (s) {
      if (!s) { irLogin(); return new Promise(function () {}); }
      return perfil();
    }).then(function (p) {
      if (!p || !p.ativo) { limpar(); irLogin(); return new Promise(function () {}); }
      if (p.must_change_password && !opts.permitirTrocaPendente) {
        location.href = ROOT + "trocar-senha.html?next=" + encodeURIComponent(caminhoAtual());
        return new Promise(function () {});
      }
      if (opts.admin && !p.is_admin) { location.href = ROOT + "index.html"; return new Promise(function () {}); }
      return p;
    });
  }

  // Protege um relatório: login + permissão no banco para o slug
  function protegerRelatorio(slug) {
    return exigirLogin().then(function (p) {
      return rpc("pode_ver_relatorio", { p_slug: slug }).then(function (ok) {
        if (!ok) { location.href = ROOT + "index.html?sem_acesso=" + encodeURIComponent(slug); return new Promise(function () {}); }
        return p;
      });
    });
  }

  // ---------- utilidades de interface ----------
  function esc(v) {
    return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function iniciais(nome, email) {
    var base = (nome || email || "?").trim();
    var partes = base.split(/[\s.@_-]+/).filter(Boolean);
    return ((partes[0] || "?")[0] + (partes.length > 1 ? partes[1][0] : "")).toUpperCase();
  }
  function toast(msg, tipo) {
    var box = document.getElementById("tc-toasts");
    if (!box) { box = document.createElement("div"); box.id = "tc-toasts"; box.setAttribute("role", "status"); document.body.appendChild(box); }
    var t = document.createElement("div");
    t.className = "tc-toast " + (tipo || "ok");
    t.textContent = msg;
    box.appendChild(t);
    setTimeout(function () { t.classList.add("sai"); setTimeout(function () { t.remove(); }, 300); }, 3800);
  }

  // Menu do usuário (avatar + nome + atalhos). el = elemento container.
  function montarMenuUsuario(el, p) {
    var primeiroNome = (p.nome || p.email).split(" ")[0];
    el.innerHTML =
      '<div class="tc-user">' +
      '<button type="button" class="tc-user-btn" aria-haspopup="menu" aria-expanded="false">' +
      '<span class="tc-avatar" aria-hidden="true">' + esc(iniciais(p.nome, p.email)) + '</span>' +
      '<span class="tc-user-nome">' + esc(primeiroNome) + '</span>' +
      '<svg width="14" height="14" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>' +
      '</button>' +
      '<div class="tc-menu" role="menu" hidden>' +
      '<div class="tc-menu-head"><strong>' + esc(p.nome || p.email) + '</strong><span>' + esc(p.email) + '</span></div>' +
      '<a role="menuitem" href="' + ROOT + 'index.html">Início</a>' +
      (p.is_admin ? '<a role="menuitem" href="' + ROOT + 'admin.html">Administração</a>' : '') +
      '<a role="menuitem" href="' + ROOT + 'trocar-senha.html?voluntario=1">Alterar senha</a>' +
      '<button type="button" role="menuitem" class="tc-sair">Sair</button>' +
      '</div></div>';
    var btn = el.querySelector(".tc-user-btn"), menu = el.querySelector(".tc-menu");
    function fechar() { menu.hidden = true; btn.setAttribute("aria-expanded", "false"); }
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      menu.hidden = !menu.hidden;
      btn.setAttribute("aria-expanded", String(!menu.hidden));
    });
    document.addEventListener("click", function (e) { if (!el.contains(e.target)) fechar(); });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") fechar(); });
    el.querySelector(".tc-sair").addEventListener("click", sair);
  }

  global.TC = {
    ROOT: ROOT,
    config: CFG,
    sessao: ler,
    sessaoValida: sessaoValida,
    login: login,
    sair: sair,
    perfil: perfil,
    trocarSenha: trocarSenha,
    exigirLogin: exigirLogin,
    protegerRelatorio: protegerRelatorio,
    destinoSeguro: destinoSeguro,
    irLogin: irLogin,
    rest: rest,
    db: db,
    rpc: rpc,
    fn: fn,
    esc: esc,
    iniciais: iniciais,
    toast: toast,
    montarMenuUsuario: montarMenuUsuario
  };
})(window);
