# capitole.awk — cititorul comun al capitolelor norgedan (pas120).
# Folosit de verifica-site.sh ([18], [19]) si de legaturi.sh: un singur fel de a
# spune ce e un capitol si cum se numeste.
#
# Capitol = de la un <h2> la urmatorul (sau </main>).  Numele lui = ancora:
# id-ul de pe <h2>, altfel id-ul ultimului <section> deschis inaintea lui.
# Nu intra in text: comentarii, script, style, nav, aside, footer.
#
# Variabile (-v):  doc, lang, site, base   — obligatorii
#                  capf   fisierul unde se scriu capitolele; gol = iesirea standard
#                  tdir, udir, lnk  — doar pentru legaturi.sh: textul fiecarui
#                         capitol (tot / fara marcaje) si trimiterile; goale = nimic
# Iesire, un rand pe capitol:  doc TAB lang TAB pozitie TAB ancora TAB titlu
# Portabil: one-true-awk (OpenBSD), mawk, gawk; LC_ALL=C.
function attr(tag, a) {
  if (match(tag, "[ \t\n]" a "=\"[^\"]*\""))
    return substr(tag, RSTART + length(a) + 3, RLENGTH - length(a) - 4)
  return ""
}
function ent(s) {
  gsub(/&nbsp;/, " ", s); gsub(/&lt;/, "<", s); gsub(/&gt;/, ">", s)
  gsub(/&quot;/, "\"", s); gsub(/&#39;/, "'", s); gsub(/&amp;/, "\\&", s)
  gsub(/[ \t\r\n]+/, " ", s)
  return s
}
# adresa -> "cale<TAB>ancora" pe site; "" pentru adrese externe
function rezolva(h,   anc, i, n, p, k, out, seg) {
  anc = ""
  i = index(h, "#"); if (i > 0) { anc = substr(h, i + 1); h = substr(h, 1, i - 1) }
  i = index(h, "?"); if (i > 0) h = substr(h, 1, i - 1)
  if (h == "") p = site
  else if (index(h, base "/") == 1) p = substr(h, length(base) + 2)
  else if (h == base) p = ""
  else if (h ~ /^[a-zA-Z][a-zA-Z0-9+.-]*:/ || h ~ /^\/\//) return ""
  else if (h ~ /^\//) p = substr(h, 2)
  else p = dir h
  n = split(p, seg, "/"); k = 0
  for (i = 1; i <= n; i++) {
    if (seg[i] == "." || (seg[i] == "" && i < n)) continue
    if (seg[i] == "..") { if (k > 0) k--; continue }
    out[++k] = seg[i]
  }
  p = ""
  for (i = 1; i <= k; i++) p = p (i > 1 ? "/" : "") out[i]
  if (p == "" || p ~ /\/$/) p = p "index.html"
  return p "\t" anc
}
BEGIN {
  RS = "<"; pos = 0; inch = 0; skip = ""; sd = 0; mark = 0; sdep = 0; incom = 0
  txtout = (tdir != "")
  sec = ""; inh2 = 0
  dir = site; sub(/[^\/]*$/, "", dir)
  bloc = " p li h2 h3 h4 div br td th tr section blockquote ul ol dd dt figcaption "
}
NR == 1 { next }
{
  # comentariile: <!-- ... --> pot cuprinde "<" si chiar "<h2"
  if (incom || substr($0, 1, 3) == "!--") {
    j = index($0, "-->")
    if (j == 0) { incom = 1; next }
    incom = 0; tag = ""; nm = "!--"; txt = substr($0, j + 3)
  } else {
    i = index($0, ">")
    if (i == 0) { tag = $0; txt = "" } else { tag = substr($0, 1, i - 1); txt = substr($0, i + 1) }
    nm = tag; sub(/[ \t\r\n].*/, "", nm); nm = tolower(nm); sub(/\/$/, "", nm)
  }

  if (skip != "") {
    if (nm == skip) sd++
    else if (nm == "/" skip && --sd == 0) skip = ""
    next
  }
  if (nm == "script" || nm == "style" || nm == "nav" || nm == "aside" || nm == "footer") {
    skip = nm; sd = 1; next
  }
  if (nm == "section") { a = attr(tag, "id"); if (a != "") sec = a }
  if (nm == "/main") inch = 0
  if (nm == "h2") {
    if (pos > 0 && txtout) { close(tf); close(uf) }
    pos++; inch = 1; inh2 = 1; ttl = ""
    anc = attr(tag, "id"); if (anc == "") anc = sec
    sec = ""
    if (txtout) {
      tf = tdir "/" doc "." lang "." pos; uf = udir "/" doc "." lang "." pos
      printf "" > tf; printf "" > uf
    }
  }
  if (nm == "span") {
    if (mark > 0) sdep++
    else if (tag ~ /[ \t\n]data-afirmatie=/) { mark = 1; sdep = 1 }
  } else if (nm == "/span" && mark > 0) {
    if (--sdep == 0) mark = 0
  }
  if (txtout && pos > 0 && inch && nm == "a") {
    h = attr(tag, "href")
    if (h != "") { r = rezolva(h); if (r != "") print doc "\t" lang "\t" pos "\t" r >> lnk }
  }
  if (pos > 0 && inch) {
    x = ent(txt)
    if (index(bloc, " " nm " ") || index(bloc, " " substr(nm, 2) " ")) x = " " x
    if (inh2) ttl = ttl x
    if (txtout) { printf "%s", x >> tf; if (!mark) printf "%s", x >> uf }
  }
  if (nm == "/h2" && inh2) {
    inh2 = 0; gsub(/^ +| +$/, "", ttl); gsub(/ +/, " ", ttl)
    if (capf != "") print doc "\t" lang "\t" pos "\t" anc "\t" ttl >> capf
    else print doc "\t" lang "\t" pos "\t" anc "\t" ttl
  }
}
END { if (pos > 0 && txtout) { close(tf); close(uf) } }
