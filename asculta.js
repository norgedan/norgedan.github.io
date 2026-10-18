/* asculta.js — vocea documentelor norgedan.github.io (RO si NO).
 *
 * Un singur fisier, incarcat de fiecare document cu
 *   <script src="/asculta.js" defer></script>
 * Citeste textul paginii cu vocea browserului (Web Speech API), bloc cu bloc:
 * paragrafe, titluri, citate, liste, casete.  Nu trimite nimic nicaieri si nu
 * foloseste servicii externe: vocea e cea instalata pe dispozitivul cititorului.
 *
 * - bara fixa, jos: Asculta / Pauza / Stop, viteza;
 * - un buton mic langa fiecare capitol (<h2>): citeste de acolo;
 * - blocul citit e evidentiat si adus in ecran;
 * - textul lung e taiat in fraze (Chrome opreste vocea la enunturi lungi);
 * - pe paginile care au deja butoane proprii (vorbeste/opreste), acestea
 *   folosesc acelasi motor, deci aceeasi voce si aceeasi taiere in fraze.
 * Limba vine din <html lang>: "ro" sau "nb"/"no"/"nn".
 */
(function () {
  'use strict';
  var S = window.speechSynthesis;
  var LANG = (document.documentElement.lang || 'ro').toLowerCase();
  var NO = /^(nb|no|nn)/.test(LANG);
  var T = NO ? {
    asculta: '🔊 Les opp', pauza: '⏸ Pause', reia: '▶ Fortsett', stop: '⏹ Stopp',
    viteza: 'Hastighet', capitol: '🔊', capitolTitlu: 'Les opp fra dette kapittelet',
    farav: 'Nettleseren din kan ikke lese opp tekst.',
    faravoce: 'Ingen norsk stemme er installert på denne enheten; opplesningen kan bli på et annet språk. Se innstillingene for tekst-til-tale.',
    bara: 'Opplesning'
  } : {
    asculta: '🔊 Ascultă', pauza: '⏸ Pauză', reia: '▶ Continuă', stop: '⏹ Stop',
    viteza: 'Viteză', capitol: '🔊', capitolTitlu: 'Ascultă de la acest capitol',
    farav: 'Browserul tău nu poate citi textul cu voce.',
    faravoce: 'Pe acest dispozitiv nu e instalată o voce românească; citirea poate ieși în altă limbă. Vezi setările de text-în-vorbire.',
    bara: 'Citire cu voce'
  };
  var LCOD = NO ? 'nb-NO' : 'ro-RO';
  var BLOC = /^(P|H1|H2|H3|H4|H5|H6|LI|BLOCKQUOTE|DT|DD|FIGCAPTION|TD|TH|PRE)$/;
  var SARI = 'script,style,noscript,nav,footer,button,select,option,svg,.audio-bar,#asculta-bara,[aria-hidden="true"]';

  var blocuri = [], idx = 0, bucati = [], bi = 0, activ = false, pauza = false, rata = 0.9;
  try { var r = parseFloat(localStorage.getItem('asculta-rata')); if (r > 0.4 && r < 2) rata = r; } catch (e) {}

  function vizibil(el) {
    if (el.closest(SARI)) return false;
    var cs = getComputedStyle(el);
    return cs.display !== 'none' && cs.visibility !== 'hidden';
  }
  function areTextPropriu(el) {
    for (var n = el.firstChild; n; n = n.nextSibling)
      if (n.nodeType === 3 && /\S/.test(n.nodeValue)) return true;
    return false;
  }
  function text(el) {
    var c = el.cloneNode(true);
    var x = c.querySelectorAll(SARI);
    for (var i = 0; i < x.length; i++) x[i].remove();
    var br = c.querySelectorAll('br');
    for (var j = 0; j < br.length; j++) br[j].replaceWith(' ');
    return (c.textContent || '').replace(/\s+/g, ' ').trim();
  }
  // blocurile de citit, in ordinea din pagina, fara dubluri (un citat nu se
  // citeste o data ca bloc si inca o data paragraf cu paragraf)
  function aduna(radacina) {
    var rez = [], ultim = null;
    var toate = radacina.querySelectorAll('*');
    for (var i = 0; i < toate.length; i++) {
      var el = toate[i];
      if (ultim && ultim.contains(el)) continue;
      var e = BLOC.test(el.tagName) || ((el.tagName === 'DIV' || el.tagName === 'SECTION') && areTextPropriu(el));
      if (!e || !vizibil(el)) continue;
      var t = text(el);
      if (t.length < 2) continue;
      rez.push({ el: el, t: t }); ultim = el;
    }
    return rez;
  }
  // fraze de cel mult ~220 de caractere
  function taie(t) {
    var f = t.match(/[^.!?;:»”"]+[.!?;:»”"]*\s*/g) || [t], out = [], cur = '';
    for (var i = 0; i < f.length; i++) {
      var s = f[i];
      while (s.length > 220) {
        var k = s.lastIndexOf(',', 220); if (k < 80) k = s.lastIndexOf(' ', 220); if (k < 1) k = 220;
        if (cur) { out.push(cur); cur = ''; }
        out.push(s.slice(0, k + 1)); s = s.slice(k + 1);
      }
      if ((cur + s).length > 220) { out.push(cur); cur = s; } else cur += s;
    }
    if (cur.trim()) out.push(cur);
    return out;
  }
  var voce = null, avertizat = false;
  function alegeVoce() {
    var v = S.getVoices() || [];
    var re = NO ? /^(nb|no|nn)\b/i : /^ro\b/i;
    voce = null;
    for (var i = 0; i < v.length; i++) if (re.test(v[i].lang.replace('_', '-'))) { voce = v[i]; if (v[i].localService) break; }
    return v.length;
  }
  function marcheaza(el) {
    var vechi = document.querySelector('.asculta-acum');
    if (vechi) vechi.classList.remove('asculta-acum');
    if (el) {
      el.classList.add('asculta-acum');
      var r = el.getBoundingClientRect();
      if (r.top < 60 || r.bottom > window.innerHeight - 90) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }
  function urmator() {
    if (!activ || pauza) return;
    if (bi >= bucati.length) {
      idx++; bi = 0;
      if (idx >= blocuri.length) { opresteTot(); return; }
      bucati = taie(blocuri[idx].t);
      marcheaza(blocuri[idx].el);
    }
    var u = new SpeechSynthesisUtterance(bucati[bi]);
    u.lang = voce ? voce.lang : LCOD; if (voce) u.voice = voce;
    u.rate = rata;
    u.onend = function () { bi++; urmator(); };
    u.onerror = function (e) { if (e.error !== 'interrupted' && e.error !== 'canceled') { bi++; urmator(); } };
    S.speak(u);
  }
  function porneste(lista, de) {
    if (!S) { alert(T.farav); return; }
    S.cancel();
    if (alegeVoce() > 0 && !voce && !avertizat) { avertizat = true; anunta(T.faravoce); }
    blocuri = lista; idx = de || 0; if (!blocuri.length) return;
    activ = true; pauza = false; bi = 0;
    bucati = taie(blocuri[idx].t);
    marcheaza(blocuri[idx].el);
    stare();
    urmator();
  }
  function opresteTot() {
    activ = false; pauza = false;
    if (S) S.cancel();
    marcheaza(null); stare();
  }
  function comutaPauza() {
    if (!activ) return;
    if (pauza) { pauza = false; urmator(); }
    else { pauza = true; S.cancel(); }   // reia de la fraza curenta
    stare();
  }

  // ---------- interfata ----------
  var bara, bAsc, bPauza, bStop, mesaj;
  function stare() {
    if (!bara) return;
    bPauza.disabled = !activ; bStop.disabled = !activ;
    bPauza.textContent = pauza ? T.reia : T.pauza;
  }
  function anunta(m) { if (mesaj) { mesaj.textContent = m; mesaj.hidden = false; } }
  function buton(eticheta, fn, titlu) {
    var b = document.createElement('button'); b.type = 'button'; b.textContent = eticheta;
    if (titlu) { b.title = titlu; b.setAttribute('aria-label', titlu); }
    b.addEventListener('click', fn); return b;
  }
  function stil() {
    var s = document.createElement('style');
    s.textContent =
      '#asculta-bara{position:fixed;right:12px;bottom:12px;z-index:9999;display:flex;flex-wrap:wrap;align-items:center;gap:6px;' +
      'max-width:calc(100vw - 24px);padding:8px 10px;background:rgba(14,18,28,.94);border:1px solid #3a4258;border-radius:10px;' +
      'font:13px/1.3 system-ui,-apple-system,"Segoe UI",sans-serif;color:#dde1ec;box-shadow:0 4px 18px rgba(0,0,0,.4)}' +
      '#asculta-bara button,#asculta-bara select{font:inherit;color:#dde1ec;background:#1d2435;border:1px solid #3a4258;border-radius:6px;padding:6px 10px;cursor:pointer}' +
      '#asculta-bara button:hover:not(:disabled){background:#2a3550}' +
      '#asculta-bara button:disabled{opacity:.45;cursor:default}' +
      '#asculta-bara label{display:flex;align-items:center;gap:4px;opacity:.85}' +
      '#asculta-bara .asculta-mesaj{flex-basis:100%;max-width:340px;font-size:12px;color:#e0b070;cursor:pointer}' +
      'body{padding-bottom:84px}' +
      '.asculta-cap{margin-left:.5em;font-size:.55em;vertical-align:middle;background:transparent;border:1px solid currentColor;border-radius:6px;' +
      'padding:2px 7px;cursor:pointer;color:inherit;opacity:.6}' +
      '.asculta-cap:hover{opacity:1}' +
      '.asculta-acum{outline:2px solid rgba(201,168,76,.75);outline-offset:4px;border-radius:3px}' +
      '@media (max-width:520px){#asculta-bara{left:8px;right:8px;bottom:8px;justify-content:center}}' +
      '@media print{#asculta-bara,.asculta-cap{display:none}}';
    document.head.appendChild(s);
  }
  function radacina() {
    return document.body;   // nav si footer sunt sarite; titlul paginii se citeste
  }
  function init() {
    if (!S) return;            // fara voce in browser: pagina ramane neschimbata
    stil();
    bara = document.createElement('div'); bara.id = 'asculta-bara';
    bara.setAttribute('role', 'region'); bara.setAttribute('aria-label', T.bara);
    bAsc = buton(T.asculta, function () { porneste(aduna(radacina()), 0); });
    bPauza = buton(T.pauza, comutaPauza);
    bStop = buton(T.stop, opresteTot);
    var lab = document.createElement('label'); lab.textContent = T.viteza + ' ';
    var sel = document.createElement('select');
    [0.75, 0.9, 1, 1.15, 1.3].forEach(function (v) {
      var o = document.createElement('option'); o.value = v; o.textContent = String(v).replace('.', ',') + '×';
      if (Math.abs(v - rata) < 0.01) o.selected = true; sel.appendChild(o);
    });
    sel.addEventListener('change', function () {
      rata = parseFloat(sel.value);
      try { localStorage.setItem('asculta-rata', String(rata)); } catch (e) {}
      if (activ && !pauza) { S.cancel(); setTimeout(urmator, 60); }   // fraza curenta, cu noua viteza
    });
    lab.appendChild(sel);
    mesaj = document.createElement('div'); mesaj.className = 'asculta-mesaj'; mesaj.hidden = true;
    mesaj.title = NO ? 'Trykk for å skjule' : 'Atinge ca să ascunzi';
    mesaj.addEventListener('click', function () { mesaj.hidden = true; });
    bara.appendChild(bAsc); bara.appendChild(bPauza); bara.appendChild(bStop); bara.appendChild(lab); bara.appendChild(mesaj);
    document.body.appendChild(bara);
    stare();

    // butoanele proprii ale paginilor vechi trec pe acelasi motor
    if (typeof window.vorbeste === 'function' || document.querySelector('.audio-bar')) {
      window.vorbeste = function (id) { var el = document.getElementById(id); if (el) porneste(aduna(el), 0); };
      window.opreste = opresteTot;
    } else {
      // un buton mic langa fiecare capitol
      var h = radacina().querySelectorAll('h2');
      for (var i = 0; i < h.length; i++) (function (h2) {
        if (!vizibil(h2)) return;
        h2.appendChild(buton(T.capitol, function () {
          var l = aduna(radacina());
          for (var k = 0; k < l.length; k++) if (l[k].el === h2 || h2.contains(l[k].el) || l[k].el.contains(h2)) { porneste(l, k); return; }
          porneste(l, 0);
        }, T.capitolTitlu)).className = 'asculta-cap';
      })(h[i]);
    }
    if (S.onvoiceschanged !== undefined) S.onvoiceschanged = alegeVoce;
    alegeVoce();
    window.addEventListener('pagehide', function () { S.cancel(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();
