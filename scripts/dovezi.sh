#!/bin/sh
# dovezi.sh (pas130) — pagina publica a dovezilor, generata din registre.
#
# Fiecare afirmatie marcata in pagini (<span data-afirmatie="id">) primeste in
# dovezi.html: textul ei din pagina (RO si NO), eticheta (FAPT, ESTIMARE,
# INTERPRETARE, CREDINTA), locurile unde apare si sursele din surse.tsv — adresa,
# data citirii, cine a citit-o.  Citatele raman in registru (le confrunta garda);
# pagina publica arata sursa, cititorul o deschide si verifica singur.
#
# O singura sursa de adevar: pagina NU se scrie de mana.  Se scrie din
# afirmatii.tsv + surse.tsv + paginile insele, iar garda ([13]) o regenereaza si o
# compara: o pagina ramasa in urma opreste push-ul (ca teme.html, L7).
#
#   sh scripts/dovezi.sh            scrie pagina generata pe iesire
#   sh scripts/dovezi.sh --scrie    rescrie dovezi.html in hub
#
# POSIX: sh, awk, sed, sort.  Fara extensii GNU.
LC_ALL=C; export LC_ALL
SD=$(cd "$(dirname "$0")" && pwd)
HUB=$(dirname "$SD")
RADACINA=${RADACINA:-$(dirname "$HUB")}
HUBNAME=$(basename "$HUB")
SITE=https://norgedan.github.io
W=$(mktemp -d /tmp/dovezi.XXXXXX) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

# lista paginilor publice: doc limba cale-pe-disc url titlu
awk -F'\t' -v R="$RADACINA" -v H="$HUBNAME" -v S="$SITE" '
  /^#/ || NF < 7 { next }
  { pre = ($3 == H) ? "" : $3 "/"
    print $1 "\tro\t" R "/" $3 "/" $4 "\t" S "/" pre $4 "\t" $6
    print $1 "\tno\t" R "/" $3 "/" $5 "\t" S "/" pre $5 "\t" $7 }' "$SD/documente.tsv" > "$W/pag"
printf 'index\tro\t%s\t%s/\tnorgedan — pagina principală\n' "$HUB/index.html" "$SITE" >> "$W/pag"
# paginile de intrare ale colectiilor (corpus/index.html are si ea afirmatii marcate)
awk -F'\t' -v H="$HUBNAME" '!/^#/ && NF >= 7 && $3 != H && !v[$3]++ { print $3 }' "$SD/documente.tsv" | while read -r r; do
  [ -f "$RADACINA/$r/index.html" ] && printf 'index-%s\tro\t%s\t%s/%s/\t%s — pagina colecției\n' "$r" "$RADACINA/$r/index.html" "$SITE" "$r" "$r"
done >> "$W/pag"

# marcajele: id doc limba ancora text — in ordinea din pagini
cat > "$W/marc.awk" <<'AWK'
function curata(t) {
  gsub(/<[^>]*>/, "", t); gsub(/[ \t\r\n]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
  return t
}
BEGIN { RS = "\001" }
{
  s = $0
  while ((i = index(s, "<!--")) > 0) { j = index(substr(s, i), "-->"); if (j == 0) { s = substr(s, 1, i - 1); break }; s = substr(s, 1, i - 1) substr(s, i + j + 2) }
  anc = ""; ord = 0
  while ((i = index(s, "<")) > 0) {
    s = substr(s, i); j = index(s, ">"); if (j == 0) break
    tag = substr(s, 1, j); s = substr(s, j + 1)
    if (tag ~ /^<(section|h2)[ >]/ && match(tag, /id="[^"]*"/)) anc = substr(tag, RSTART + 4, RLENGTH - 5)
    if (tag ~ /^<span data-afirmatie="/) {
      id = tag; sub(/^<span data-afirmatie="/, "", id); sub(/".*/, "", id)
      d = 1; txt = ""
      while (d > 0 && (k = index(s, "<")) > 0) {
        txt = txt substr(s, 1, k - 1); s = substr(s, k); m = index(s, ">"); if (m == 0) break
        t2 = substr(s, 1, m); s = substr(s, m + 1)
        if (t2 ~ /^<span[ >]/) d++
        else if (t2 ~ /^<\/span>/) { d--; if (d == 0) break }
        txt = txt t2
      }
      ord++
      print id "\t" DOC "\t" LANG "\t" anc "\t" curata(txt) "\t" ord
    }
  }
}
AWK
: > "$W/marc"
while IFS="$(printf '\t')" read -r doc lang f url titlu; do
  [ -f "$f" ] || { echo "dovezi.sh: lipseste $f" >&2; exit 1; }
  awk -v DOC="$doc" -v LANG="$lang" -f "$W/marc.awk" "$f" >> "$W/marc"
done < "$W/pag"
[ -s "$W/marc" ] || { echo "dovezi.sh: niciun marcaj citit (santinela)" >&2; exit 1; }

cat > "$W/gen.awk" <<'AWK'
function esc(t) { gsub(/&/, "\\&amp;", t); gsub(/</, "\\&lt;", t); gsub(/>/, "\\&gt;", t); gsub(/"/, "\\&quot;", t); return t }
function domeniu(u,   d) { d = u; sub(/^https?:\/\//, "", d); sub(/\/.*/, "", d); sub(/^www\./, "", d); return d }
function nivel(n) { return n == "P" ? "primară · primær" : (n == "S" ? "secundară · sekundær" : "terțiară · tertiær") }
function cine(c) { return c == "claude" ? "Claude" : (c == "bogdan" ? "Bogdan" : c) }
function eticheta(e) {
  if (e == "FAPT") return "FAPT · FAKTUM"
  if (e == "ESTIMARE") return "ESTIMARE · ANSLAG"
  if (e == "INTERPRETARE") return "INTERPRETARE · TOLKNING"
  return "CREDINȚĂ · TRO"
}
BEGIN {
  FS = "\t"
  while ((getline l < PAG) > 0) { split(l, x, "\t"); url[x[1] "\t" x[2]] = x[4]; tit[x[1] "\t" x[2]] = x[5]; if (!(x[1] in dord)) { dord[x[1]] = ++nd; dlist[nd] = x[1] } }
  while ((getline l < AF) > 0) { if (l ~ /^#/) continue; split(l, x, "\t"); if (x[1] == "") continue; et[x[1]] = x[2]; st[x[1]] = x[3]; sr[x[1]] = x[5]; rev[x[1]] = x[8] }
  while ((getline l < SR) > 0) { if (l ~ /^#/) continue; split(l, x, "\t"); if (x[1] == "") continue; ns[x[1]]++; s_n[x[1], ns[x[1]]] = x[2]; s_u[x[1], ns[x[1]]] = x[3]; s_d[x[1], ns[x[1]]] = x[4]; s_c[x[1], ns[x[1]]] = x[5] }
  while ((getline l < DAT) > 0) { if (l ~ /^#/) continue; split(l, x, " "); if (x[1] != "") datorie[x[1]] = 1 }
}
{ id = $1; d = $2; lg = $3
  if (!(id in prim)) { prim[id] = d; po[d] = po[d] " " id }
  if (lg == "ro" && !((id, "ro") in tx)) tx[id, "ro"] = $5
  if (lg == "no" && !((id, "no") in tx)) tx[id, "no"] = $5
  k = d "\t" lg "\t" $4
  if (!((id, k) in vazut)) { vazut[id, k] = 1; nl[id]++; l_d[id, nl[id]] = d; l_l[id, nl[id]] = lg; l_a[id, nl[id]] = $4 }
}
END {
  for (q = 1; q <= nd; q++) {
    d = dlist[q]; if (po[d] == "") continue
    n = split(po[d], ids, " ")
    printf "<h2 class=\"doc\">%s</h2>\n", esc(tit[d "\tro"])
    for (r = 1; r <= n; r++) {
      id = ids[r]; if (id == "") continue
      printf "<section class=\"af\" id=\"%s\">\n", id
      printf "<p class=\"t\">%s</p>\n", esc(tx[id, "ro"])
      if ((id, "no") in tx) printf "<p class=\"t no\">%s</p>\n", esc(tx[id, "no"])
      printf "<p><span class=\"et\">Eticheta · Etikett</span>%s", (id in et) ? eticheta(et[id]) : "NEÎNREGISTRATĂ"
      if (rev[id] != "" && rev[id] != "-") printf " — de reverificat până la · etterprøves innen %s", rev[id]
      printf "</p>\n<p><span class=\"et\">Apare în · Finnes i</span>"
      for (z = 1; z <= nl[id]; z++) {
        dd = l_d[id, z]; u = url[dd "\t" l_l[id, z]]; a = l_a[id, z]
        printf "%s<a href=\"%s%s\">%s %s</a>", (z > 1 ? " · " : ""), u, (a != "" ? "#" a : ""), (dd == "index" ? "pagina principală" : (dd ~ /^index-/ ? "pagina colecției " substr(dd, 7) : dd (a != "" ? "#" a : ""))), toupper(l_l[id, z])
      }
      printf "</p>\n<span class=\"et\">Surse · Kilder</span>\n"
      if (ns[id] > 0) {
        printf "<ul>\n"
        # o adresa cu mai multe citate apare o data; cititorii ei se aduna
        for (z = 1; z <= ns[id]; z++) {
          u = s_u[id, z]
          if ((id, u) in fu) { if (index(" " fc[id, u] ", ", " " cine(s_c[id, z]) ",") == 0) fc[id, u] = fc[id, u] ", " cine(s_c[id, z]); continue }
          fu[id, u] = ++nu; fo[nu] = z; fc[id, u] = cine(s_c[id, z])
        }
        for (z = 1; z <= ns[id]; z++) {
          u = s_u[id, z]; if (fo[fu[id, u]] != z) continue
          printf "<li><a href=\"%s\">%s</a> — %s; citită · lest %s, %s</li>\n", esc(u), esc(domeniu(u)), nivel(s_n[id, z]), s_d[id, z], fc[id, u]
        }
        printf "</ul>\n"
      } else if (et[id] == "INTERPRETARE") {
        printf "<p class=\"m\">Interpretare, nu fapt măsurat · Tolkning, ikke et målt faktum. Temeiul · Grunnlaget: %s</p>\n", esc(sr[id])
      } else if (et[id] == "CREDINTA") {
        printf "<p class=\"m\">Credință, nu fapt de dovedit · Tro, ikke et faktum å bevise. Temeiul · Grunnlaget: %s</p>\n", esc(sr[id])
      } else {
        printf "<p class=\"m\">Sursa notată · Kilden notert: %s — dovada cu adresă și dată e în lucru · beviset med adresse og dato er under arbeid%s.</p>\n", esc(sr[id]), (id in datorie ? " (verificată înainte de pas67)" : "")
      }
      printf "</section>\n"
    }
  }
}
AWK

N=$(cut -f1 "$W/marc" | sort -u | wc -l | tr -d ' ')
{
cat <<'HTML'
<!DOCTYPE html>
<html lang="ro">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Dovezile afirmațiilor · Bevisene for påstandene — norgedan</title>
<meta name="description" content="Fiecare afirmație marcată din documentele norgedan, cu eticheta ei și cu sursele pe care cititorul le poate deschide singur. · Hver markert påstand i norgedan-dokumentene, med etikett og kildene leseren selv kan åpne.">
<link rel="canonical" href="https://norgedan.github.io/dovezi.html">
<style>
:root{--bg:#0d0f14;--fg:#e8e6e1;--muted:#9a978f;--gold:#d4a843;--line:#2a2d36;}
body{margin:0;background:var(--bg);color:var(--fg);font-family:Georgia,"Times New Roman",serif;line-height:1.6;}
main{max-width:820px;margin:0 auto;padding:1rem 1.2rem 3rem;}
a{color:var(--gold);}
.nd-nav-sus{max-width:820px;margin:0 auto;padding:.8rem 1.2rem 0;font-size:.85rem;}
h1{color:var(--gold);font-size:1.7rem;margin:1.2rem 0 .3rem;}
h2.doc{color:var(--gold);font-size:1.2rem;margin:2.2rem 0 .8rem;border-bottom:1px solid var(--line);padding-bottom:.3rem;}
.sub{color:var(--muted);font-size:.95rem;margin:0 0 2rem;}
.af{border:1px dashed rgba(212,168,67,.45);border-radius:6px;padding:.8rem 1.1rem;margin:0 0 1rem;}
.af p{margin:.2rem 0 .5rem;}
.t{font-size:1.02rem;}
.t.no{color:var(--muted);font-size:.95rem;}
.et{color:var(--muted);font-size:.85rem;display:block;}
.m{color:var(--muted);font-size:.92rem;}
ul{margin:.2rem 0 .3rem;padding-left:1.3rem;}
li{margin:.2rem 0;}
.gen{color:var(--muted);font-size:.8rem;margin-top:2rem;border-top:1px solid var(--line);padding-top:1rem;}
</style>
</head>
<body>
<nav class="nd-nav-sus"><a href="https://norgedan.github.io/">← norgedan · pagina principală · forsiden</a></nav>
<main>
<h1>Dovezile afirmațiilor · Bevisene for påstandene</h1>
<p class="sub">Afirmațiile de fond din documente sunt marcate și verificate la sursă. Aici fiecare are eticheta ei — FAPT, ESTIMARE, INTERPRETARE sau CREDINȚĂ — și sursele, cu adresa și data citirii: deschideți-le și verificați singuri. · De sentrale påstandene i dokumentene er markert og kontrollert mot kilden. Her har hver sin etikett og kildene, med adresse og lesedato: åpne dem og kontroller selv.</p>
HTML
awk -v PAG="$W/pag" -v AF="$SD/afirmatii.tsv" -v SR="$SD/surse.tsv" -v DAT="$SD/surse-datorie.txt" -f "$W/gen.awk" "$W/marc"
printf '<p class="gen">Pagină generată din registrele scripts/afirmatii.tsv și scripts/surse.tsv (scripts/dovezi.sh); %s afirmații. Nu se scrie de mână. · Siden er generert fra registrene; %s påstander. Den skrives ikke for hånd.</p>\n' "$N" "$N"
cat <<'HTML'
</main>
</body>
</html>
HTML
} > "$W/dovezi.html"

if [ "${1:-}" = "--scrie" ]; then cp "$W/dovezi.html" "$HUB/dovezi.html" && echo "scris: $HUB/dovezi.html ($N afirmatii)"
else cat "$W/dovezi.html"; fi
