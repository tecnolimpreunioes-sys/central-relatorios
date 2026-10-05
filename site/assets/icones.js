// Ícones de linha (24x24, traço 1.8) usados nas áreas e relatórios.
(function (g) {
  var P = {
    pessoas: '<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c.6-3.2 2.8-5 5.5-5s4.9 1.8 5.5 5"/><circle cx="17" cy="9" r="2.4"/><path d="M15.8 14.2c2.3.2 4 1.8 4.6 4.8"/>',
    moeda: '<rect x="3" y="6" width="18" height="12" rx="2.5"/><circle cx="12" cy="12" r="2.6"/><path d="M6.5 9.5v5M17.5 9.5v5"/>',
    operacao: '<path d="M4 20V10l5-3v13M9 20V7l6-3v16M15 20V9l5 2v9"/><path d="M3 20h18"/>',
    ti: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/><path d="M9.5 8.5 7.5 10l2 1.5M14.5 8.5l2 1.5-2 1.5"/>',
    pasta: '<path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
    grafico: '<path d="M4 20V4M4 20h16"/><path d="M8 16v-4M12 16V8M16 16v-6"/>',
    escudo: '<path d="M12 3.5 5 6v5.5c0 4.2 2.9 7.6 7 9 4.1-1.4 7-4.8 7-9V6z"/><path d="m9.2 12 2 2 3.8-4"/>',
    caminhao: '<path d="M3 6.5h11v9H3zM14 9.5h3.5l3 3v3H14"/><circle cx="7" cy="17.5" r="1.8"/><circle cx="17" cy="17.5" r="1.8"/>',
    saude: '<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/><path d="M9 11h2v-2h2v2h2v2h-2v2h-2v-2H9z"/>',
    predio: '<path d="M5 20V5.5A1.5 1.5 0 0 1 6.5 4h7A1.5 1.5 0 0 1 15 5.5V20M15 10h3.5A1.5 1.5 0 0 1 20 11.5V20M3 20h18"/><path d="M8 8h1M11 8h1M8 11.5h1M11 11.5h1M8 15h1M11 15h1"/>',
    documento: '<path d="M7 3.5h7l4 4V19a1.5 1.5 0 0 1-1.5 1.5h-9.5A1.5 1.5 0 0 1 5.5 19V5A1.5 1.5 0 0 1 7 3.5z"/><path d="M14 3.5V8h4M8.5 12.5h7M8.5 16h5"/>',
    cadeado: '<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    seta: '<path d="M5 12h14M13 6l6 6-6 6"/>',
    busca: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>',
    voltar: '<path d="M19 12H5M11 6l-6 6 6 6"/>',
    mais: '<path d="M12 5v14M5 12h14"/>',
    lista: '<path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1"/><circle cx="4.5" cy="12" r="1"/><circle cx="4.5" cy="18" r="1"/>',
    grade: '<rect x="4" y="4" width="7" height="7" rx="1.5"/><rect x="13" y="4" width="7" height="7" rx="1.5"/><rect x="4" y="13" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/>',
    olho: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    olhoOff: '<path d="M3 3l18 18M10.6 6a9.6 9.6 0 0 1 1.4-.1c6 0 9.5 6.1 9.5 6.1a17 17 0 0 1-3 3.6M6.5 7.3C3.9 9 2.5 12 2.5 12s3.5 6.5 9.5 6.5c1.7 0 3.2-.5 4.5-1.2"/><path d="M9.9 10a3 3 0 0 0 4.1 4.1"/>',
    check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
    x: '<path d="M6 6l12 12M18 6 6 18"/>'
  };
  g.TCIcone = function (nome, tam, extra) {
    var t = tam || 22;
    return '<svg class="tc-ico ' + (extra || "") + '" width="' + t + '" height="' + t + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (P[nome] || P.pasta) + "</svg>";
  };
  g.TCIcone.nomes = ["pessoas", "moeda", "operacao", "ti", "pasta", "grafico", "escudo", "caminhao", "saude", "predio", "documento"];
})(window);
