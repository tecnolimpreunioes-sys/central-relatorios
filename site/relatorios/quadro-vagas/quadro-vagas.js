// Quadro de Vagas (FPRF307 — Relação de Funcionários) — layout em tela e Excel.
// Formulário para preenchimento à caneta: as linhas de colaborador saem em branco
// (uma por colaborador ativo no cargo/local, como no relatório do Senior).
// Formato de "dados" (gravado pelo worker em central.qv_solicitacoes.resultado):
//   { data_emissao: "2026-10-05", competencia: "2026-10",
//     locais: [{ codloc, nomloc, endereco,
//                cargos: [{ codcar, titulo, autorizado, efetivo, linhas }] }] }
(function (global) {
  "use strict";

  var RE_EMPRESAS = /^\d{1,4}(-\d{1,4})?(,\d{1,4}(-\d{1,4})?)*$/;
  var RE_LOCAIS = /^\d+(\.\d+)*(==)?(,\d+(\.\d+)*(==)?)*$/;

  var COLUNAS = [ // largura em caracteres no Excel (cabe em A4 paisagem a 100%)
    { titulo: "",           largura: 10 },  // A cadastro (código do cargo no cabeçalho)
    { titulo: "",           largura: 38 },  // B nome (título do cargo no cabeçalho)
    { titulo: "Salário",    largura: 12 },
    { titulo: "C. Hora",    largura: 9 },
    { titulo: "VT",         largura: 7 },
    { titulo: "Admissão",   largura: 12 },
    { titulo: "Observação", largura: 47 }
  ];

  function limpar(v) { return String(v == null ? "" : v).replace(/\s+/g, ""); }
  function validarEmpresas(v) {
    var s = limpar(v);
    if (!RE_EMPRESAS.test(s)) throw new Error("Empresa inválida. Use o código (ex.: 3), lista (1,3) ou faixa (1-5).");
    return s;
  }
  function validarLocais(v) {
    var s = limpar(v).replace(/"/g, "");
    if (s === "") return "";
    if (!RE_LOCAIS.test(s)) throw new Error('Local inválido. Use o código (ex.: 3.111.1.1) ou 3.111== para todos abaixo de 3.111.');
    return s;
  }

  function fmtData(iso) {
    var p = String(iso || "").slice(0, 10).split("-");
    return p.length === 3 ? p[2] + "/" + p[1] + "/" + p[0] : "";
  }
  function nomeArquivo(iso) { return "quadro de vagas - " + fmtData(iso).replace(/\//g, "-") + ".xlsx"; }
  function esc(v) {
    return String(v == null ? "" : v).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function totais(dados) {
    var t = { locais: 0, cargos: 0, colaboradores: 0, autorizado: 0, efetivo: 0 };
    (dados.locais || []).forEach(function (l) {
      t.locais++;
      (l.cargos || []).forEach(function (c) {
        t.cargos++;
        t.colaboradores += c.linhas || 0;
        t.autorizado += c.autorizado || 0;
        t.efetivo += c.efetivo || 0;
      });
    });
    return t;
  }
  function fmtInt(n) { return Number(n || 0).toLocaleString("pt-BR"); }

  // ---------- tela (prévia fiel ao papel) ----------
  function renderizar(dados, filtros) {
    var h = [];
    h.push('<table class="qv"><colgroup>');
    COLUNAS.forEach(function (c) { h.push('<col style="width:' + c.largura + 'ch">'); });
    h.push('</colgroup><thead>');
    h.push('<tr class="qv-titulo"><th colspan="6">RELAÇÃO DE FUNCIONÁRIOS</th><th class="qv-data">Data: ' + esc(fmtData(dados.data_emissao)) + '</th></tr>');
    h.push('<tr class="qv-filtros"><th colspan="7">' + esc(textoFiltros(dados, filtros)) + '</th></tr>');
    h.push('</thead>');
    var t = totais(dados); // só no início do relatório (1ª página), como no Senior
    h.push('<tbody class="qv-totais"><tr><td colspan="2">TOTAL GERAL de COLABORADORES: <strong>' + fmtInt(t.colaboradores) + '</strong></td>' +
      '<td colspan="3">TOTAL GERAL AUTORIZADO: <strong>' + fmtInt(t.autorizado) + '</strong></td>' +
      '<td colspan="2">TOTAL GERAL EFETIVO: <strong>' + fmtInt(t.efetivo) + '</strong></td></tr>' +
      '<tr class="qv-espaco"><td colspan="7"></td></tr></tbody>');
    (dados.locais || []).forEach(function (l, i) {
      h.push('<tbody class="qv-local' + (i ? ' qv-quebra' : '') + '">');
      h.push('<tr class="qv-local-nome"><td colspan="7"><strong>' + esc(l.nomloc) + '</strong><span class="qv-local-cod">Local: <strong>' + esc(l.codloc) + '</strong></span></td></tr>');
      h.push('<tr class="qv-endereco"><td colspan="7">Endereço: <strong>' + esc(l.endereco) + '</strong></td></tr>');
      h.push('</tbody>');
      (l.cargos || []).forEach(function (c) {
        h.push('<tbody class="qv-cargo">');
        h.push('<tr class="qv-cargo-cab"><th>' + esc(c.codcar) + '</th><th class="qv-esq">' + esc(c.titulo) + '</th>');
        COLUNAS.slice(2).forEach(function (col) { h.push('<th>' + col.titulo + '</th>'); });
        h.push('</tr>');
        h.push('<tr class="qv-quadro"><td colspan="2"><strong>QUADRO VAGA &gt;&gt;&gt;</strong>' +
          '<span class="qv-num">Autorizado: <strong>' + esc(c.autorizado) + '</strong></span>' +
          '<span class="qv-num">Efetivo: <strong>' + esc(c.efetivo) + '</strong></span></td>' +
          '<td colspan="2"><strong>' + esc(l.codloc) + '</strong></td><td colspan="3"><strong>' + esc(l.nomloc) + '</strong></td></tr>');
        for (var n = 0; n < (c.linhas || 0); n++) h.push('<tr class="qv-linha"><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>');
        h.push('<tr class="qv-espaco"><td colspan="7"></td></tr>');
        h.push('</tbody>');
      });
    });
    h.push('</table>');
    return h.join("");
  }

  function textoFiltros(dados, filtros) {
    filtros = filtros || {};
    var p = ["Empresa: " + (filtros.empresas || "—"), "Local: " + (filtros.locais || "todos")];
    if (dados.competencia) p.push("Quadro (competência): " + dados.competencia.split("-").reverse().join("/"));
    return p.join("   ·   ");
  }

  // ---------- Excel (pronto para imprimir) ----------
  var COR = { marca: "FF004773", cab: "FFD9E3EC", quadro: "FFF2F5F8", linha: "FF7F8896", texto: "FF161C2D", sutil: "FF66707F" };
  var ALTURA = { titulo: 24, filtros: 16, totais: 22, local: 22, endereco: 17, cab: 19, quadro: 17, linha: 22, espaco: 6 };
  // A4 paisagem = 595pt de altura; menos margens (0,5" + 0,6") e linhas de título repetidas, com folga.
  var CAPACIDADE_PAGINA = (595 - 36 - 43 - ALTURA.titulo - ALTURA.filtros) * 0.98;

  function fonte(extra) {
    var f = { name: "Arial", size: 9, color: { argb: COR.texto } };
    for (var k in extra) f[k] = extra[k];
    return f;
  }
  function borda(cor, estilo) {
    var b = { style: estilo || "thin", color: { argb: cor } };
    return { top: b, left: b, bottom: b, right: b };
  }

  function gerarExcel(ExcelJS, dados, filtros) {
    var wb = new ExcelJS.Workbook();
    wb.creator = "Central de Relatórios Tecnolimp";
    wb.created = new Date();
    var dataBR = fmtData(dados.data_emissao);
    var ws = wb.addWorksheet("Quadro de Vagas", {
      views: [{ showGridLines: false }],
      pageSetup: {
        paperSize: 9, orientation: "landscape", scale: 100, fitToPage: false,
        horizontalCentered: true, printTitlesRow: "1:2",
        margins: { left: 0.4, right: 0.4, top: 0.5, bottom: 0.6, header: 0.25, footer: 0.3 }
      },
      headerFooter: { oddFooter: "&L&\"Arial\"&8Quadro de vagas — emissão " + dataBR + "&R&\"Arial\"&8Página &P de &N" }
    });
    ws.columns = COLUNAS.map(function (c) { return { width: c.largura }; });

    var r = 1;
    function linha(altura) { var row = ws.getRow(r); row.height = altura; r++; return row; }
    function mesclar(row, de, ate) { ws.mergeCells(row.number, de, row.number, ate); return row.getCell(de); }

    // títulos (repetem em todas as páginas)
    var t = linha(ALTURA.titulo);
    var ct = mesclar(t, 1, 6);
    ct.value = "RELAÇÃO DE FUNCIONÁRIOS";
    ct.font = fonte({ size: 14, bold: true, color: { argb: COR.marca } });
    ct.alignment = { horizontal: "center", vertical: "middle" };
    t.getCell(7).value = "Data: " + dataBR;
    t.getCell(7).font = fonte({ size: 10, bold: true });
    t.getCell(7).alignment = { horizontal: "right", vertical: "middle" };
    var f = linha(ALTURA.filtros);
    var cf = mesclar(f, 1, 7);
    cf.value = textoFiltros(dados, filtros);
    cf.font = fonte({ size: 8, color: { argb: COR.sutil } });
    cf.alignment = { horizontal: "center", vertical: "middle" };
    cf.border = { bottom: { style: "medium", color: { argb: COR.marca } } };

    // totais gerais: só no início do relatório (não repetem nas páginas seguintes)
    var tg = totais(dados);
    var lt = linha(ALTURA.totais);
    [[1, 2, "TOTAL GERAL de COLABORADORES: ", tg.colaboradores], [3, 5, "TOTAL GERAL AUTORIZADO: ", tg.autorizado],
     [6, 7, "TOTAL GERAL EFETIVO: ", tg.efetivo]].forEach(function (g) {
      var cell = mesclar(lt, g[0], g[1]);
      cell.value = { richText: [{ text: g[2], font: fonte({ size: 10, bold: true }) },
                                { text: fmtInt(g[3]), font: fonte({ size: 11, bold: true, color: { argb: COR.marca } }) }] };
      cell.alignment = { horizontal: g[0] === 1 ? "left" : "center", vertical: "middle", indent: g[0] === 1 ? 1 : 0 };
    });
    for (var k0 = 1; k0 <= 7; k0++) {
      lt.getCell(k0).fill = { type: "pattern", pattern: "solid", fgColor: { argb: COR.quadro } };
      lt.getCell(k0).border = { top: { style: "medium", color: { argb: COR.texto } }, bottom: { style: "medium", color: { argb: COR.texto } } };
    }
    linha(ALTURA.espaco);

    var usado = ALTURA.totais + ALTURA.espaco;
    function quebraAntes() { ws.getRow(r - 1).addPageBreak(); usado = 0; }
    function cabe(altura) {
      if (usado > 0 && usado + altura > CAPACIDADE_PAGINA) quebraAntes();
      usado = (usado + altura) % CAPACIDADE_PAGINA;
    }

    (dados.locais || []).forEach(function (l, i) {
      if (i > 0) quebraAntes(); // cada local começa em página nova
      usado += ALTURA.local + ALTURA.endereco;

      var ln = linha(ALTURA.local);
      var cl = mesclar(ln, 1, 7);
      cl.value = { richText: [
        { text: l.nomloc || "", font: fonte({ size: 11, bold: true, color: { argb: "FFFFFFFF" } }) },
        { text: "        Local: ", font: fonte({ size: 10, color: { argb: "FFFFFFFF" } }) },
        { text: l.codloc || "", font: fonte({ size: 11, bold: true, color: { argb: "FFFFFFFF" } }) }
      ] };
      cl.fill = { type: "pattern", pattern: "solid", fgColor: { argb: COR.marca } };
      cl.alignment = { horizontal: "center", vertical: "middle" };

      var le = linha(ALTURA.endereco);
      var ce = mesclar(le, 1, 7);
      ce.value = { richText: [
        { text: "Endereço: ", font: fonte({ color: { argb: COR.sutil } }) },
        { text: l.endereco || "", font: fonte({ bold: true }) }
      ] };
      ce.alignment = { vertical: "middle", indent: 1 };
      ce.border = { bottom: { style: "thin", color: { argb: COR.linha } } };

      (l.cargos || []).forEach(function (c) {
        cabe(alturaCargo(c));
        var cab = linha(ALTURA.cab);
        cab.getCell(1).value = c.codcar;
        cab.getCell(2).value = c.titulo;
        COLUNAS.forEach(function (col, k) {
          var cell = cab.getCell(k + 1);
          if (k > 1) cell.value = col.titulo;
          cell.font = fonte({ bold: true });
          cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb: COR.cab } };
          cell.border = borda(COR.linha);
          cell.alignment = { horizontal: k === 1 ? "left" : "center", vertical: "middle", indent: k === 1 ? 1 : 0 };
        });

        var q = linha(ALTURA.quadro);
        var cq = mesclar(q, 1, 2);
        cq.value = { richText: [
          { text: "QUADRO VAGA >>>", font: fonte({ bold: true }) },
          { text: "     Autorizado: ", font: fonte() }, { text: String(c.autorizado), font: fonte({ bold: true }) },
          { text: "     Efetivo: ", font: fonte() }, { text: String(c.efetivo), font: fonte({ bold: true }) }
        ] };
        var cc = mesclar(q, 3, 4); cc.value = l.codloc;
        var cn = mesclar(q, 5, 7); cn.value = l.nomloc;
        [cq, cc, cn].forEach(function (cell, k) {
          if (k) cell.font = fonte({ bold: true });
          cell.alignment = { horizontal: k === 0 ? "left" : "center", vertical: "middle", indent: k === 0 ? 1 : 0 };
        });
        for (var k = 1; k <= 7; k++) {
          q.getCell(k).fill = { type: "pattern", pattern: "solid", fgColor: { argb: COR.quadro } };
          q.getCell(k).border = borda(COR.linha);
        }

        for (var n = 0; n < (c.linhas || 0); n++) {
          var lb = linha(ALTURA.linha);
          for (var j = 1; j <= 7; j++) lb.getCell(j).border = borda(COR.linha);
        }
        linha(ALTURA.espaco);
      });
    });

    ws.pageSetup.printArea = "A1:G" + Math.max(r - 1, 2);
    return wb.xlsx.writeBuffer();
  }

  function alturaCargo(c) { return ALTURA.cab + ALTURA.quadro + (c.linhas || 0) * ALTURA.linha + ALTURA.espaco; }

  // Navegador: carrega o ExcelJS só na 1ª exportação e baixa o arquivo.
  var carregando = null;
  function carregarExcelJS(src) {
    if (global.ExcelJS) return Promise.resolve(global.ExcelJS);
    if (!carregando) carregando = new Promise(function (ok, falha) {
      var s = document.createElement("script");
      s.src = src;
      s.onload = function () { ok(global.ExcelJS); };
      s.onerror = function () { carregando = null; falha(new Error("Não foi possível carregar o gerador de Excel.")); };
      document.head.appendChild(s);
    });
    return carregando;
  }
  function baixarExcel(dados, filtros, srcExcelJS) {
    return carregarExcelJS(srcExcelJS).then(function (ExcelJS) {
      return gerarExcel(ExcelJS, dados, filtros);
    }).then(function (buf) {
      var blob = new Blob([buf], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
      var a = document.createElement("a");
      a.href = URL.createObjectURL(blob);
      a.download = nomeArquivo(dados.data_emissao);
      document.body.appendChild(a);
      a.click();
      setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    });
  }

  var QV = {
    validarEmpresas: validarEmpresas, validarLocais: validarLocais,
    fmtData: fmtData, fmtInt: fmtInt, nomeArquivo: nomeArquivo, totais: totais,
    renderizar: renderizar, gerarExcel: gerarExcel, baixarExcel: baixarExcel
  };
  if (typeof module !== "undefined" && module.exports) module.exports = QV;
  else global.QV = QV;
})(typeof window !== "undefined" ? window : globalThis);
