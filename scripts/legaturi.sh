#!/bin/sh
# legaturi.sh — legaturile dintre documente, capitole si teme (pas118).
#
# Un singur cod pentru legaturi: garda (verifica-site.sh, [23]) il ruleaza si ii
# citeste iesirea; separat, scriptul da detaliile complete si rescrie teme.html.
#
#   sh ~/norgedan.github.io/scripts/legaturi.sh           verifica straturile L1-L7
#   sh ~/norgedan.github.io/scripts/legaturi.sh --scrie   rescrie teme.html din teme.tsv
#
# Din pas121 ruleaza si in garda, ca sectiunea [23] (LEGATURI_GARDA=1: fara bannerul
# propriu, L3 pe scurt — lista completa ramane aici, in rularea separata).
#
# Straturile:
#   L1  ancorele capitolelor: fiecare <h2> are ancora (id pe h2 sau pe <section>-ul
#       lui), unica in fisier, aceleasi ancore in aceeasi ordine in RO si NO
#   L2  o singura casa pe tema: teme.tsv corect, casa exista in RO si NO
#   L3  legaturi lipsa: capitolele care trateaza o tema si nu trimit spre casa ei
#   L4  faptele: cifre nemarcate dintr-un capitol care apar si in casa temei —
#       acelasi fapt in doua locuri, fara id comun de afirmatie
#   L5  paritatea RO-NO a trimiterilor spre capitole din alte documente
#   L6  orfanii: capitole fara nicio tema si fara nicio trimitere primita;
#       case de tema spre care nu trimite niciun alt document
#   L7  pagina teme.html == ce se genereaza acum din teme.tsv
#   L8  cifrele RO-NO: numere care apar intr-o limba si lipsesc din cealalta (pas122)
#   L9  randurile de tema <p class="nd-tema">: doar navigare spre casele din teme.tsv
#       (pas123) — garda [18] nu le pune in amprenta, deci trebuie sa nu poata duce
#       nimic altceva decat legaturi
#       (teme.html sta in radacina hub-ului, publica si in sitemap-hub.xml; garda o
#       cunoaste ca pagina de structura din pas119.)
#
# PROBLEMA = stricat (L1, L2, L5, L7, L9); ATENTIE = de lucru (L3, L4, L6, L8).
# Iesire 1 daca exista cel putin o PROBLEMA.
#
# POSIX: sh (ksh pe OpenBSD), awk (one-true-awk pe OpenBSD), sort, cmp, mktemp.
# LC_ALL=C: awk-ul lucreaza pe octeti, la fel pe orice sistem.

LC_ALL=C; export LC_ALL
PRAG=3          # de cate ori revine tiparul ca un capitol sa "trateze" tema
BASE=https://norgedan.github.io

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 2
HUB=$(dirname "$SCRIPT_DIR")
RADACINA=$(dirname "$HUB")
HUBNAME=$(basename "$HUB")
MAN="$SCRIPT_DIR/documente.tsv"
TEME="$SCRIPT_DIR/teme.tsv"
INDEX="$HUB/teme.html"

MOD=verifica
case "${1:-}" in
  "") ;;
  --scrie) MOD=scrie ;;
  *) echo "utilizare: sh $0 [--scrie]" >&2; exit 2 ;;
esac

for f in "$MAN" "$TEME"; do
  [ -f "$f" ] || { echo "lipseste $f" >&2; exit 2; }
done

W=$(mktemp -d "${TMPDIR:-/tmp}/legaturi.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
trap 'exit 2' INT TERM HUP
mkdir "$W/t" "$W/u"

probleme=0
titlu() { echo ""; echo "[$1] $2"; }
ok()    { echo "  OK       $1"; }
atentie() { echo "  ATENTIE  $1"; }
problema() { echo "  PROBLEMA $1"; probleme=$((probleme + 1)); }
# randurile unui fisier, indentate, sub o ATENTIE/PROBLEMA
lista() { while IFS= read -r l; do echo "             $l"; done < "$1"; }

GARDA=${LEGATURI_GARDA:-0}
if [ "$GARDA" != 1 ]; then
  echo "===================================================="
  echo "  legaturi.sh  ·  pas121  ·  mod: $MOD"
  echo "  radacina clonelor: $RADACINA"
  echo "===================================================="
fi

# ── fisierele documentelor: doc lang repo cale site ─────────────────
# site = calea pe norgedan.github.io (hub-ul la radacina, celelalte sub /repo/)
awk -F'\t' -v hub="$HUBNAME" '
  /^#/ || NF < 7 { next }
  { s = ($3 == hub) ? "" : $3 "/"
    print $1 "\tro\t" $3 "\t" $4 "\t" s $4
    print $1 "\tno\t" $3 "\t" $5 "\t" s $5 }' "$MAN" > "$W/f"

# ── extragerea: capitole, texte, trimiteri ─────────────────────────
# Cititorul comun: scripts/capitole.awk (acelasi ca in garda, din pas120).

: > "$W/cap"; : > "$W/lnk"; : > "$W/nt"
while IFS="$(printf '\t')" read -r doc lang repo cale site; do
  fis="$RADACINA/$repo/$cale"
  [ -f "$fis" ] || { echo "lipseste $fis" >&2; exit 2; }
  awk -v doc="$doc" -v lang="$lang" -v site="$site" -v base="$BASE" \
      -v tdir="$W/t" -v udir="$W/u" -v lnk="$W/lnk" -v capf="$W/cap" -v ntf="$W/nt" \
      -f "$SCRIPT_DIR/capitole.awk" "$fis" || exit 2
done < "$W/f"

# trimiterile, cu tinta tradusa in document: doc lang pos tdoc tlang tanc
awk -F'\t' 'FILENAME == ARGV[1] { d[$5] = $1 "\t" $2; next }
  { t = ($4 in d) ? d[$4] : "-\t-"; print $1 "\t" $2 "\t" $3 "\t" t "\t" $5 }' \
  "$W/f" "$W/lnk" > "$W/trim"

# harta capitolelor RO -> NO: doc rpos npos nanc ranc  (scripts/harta.awk, comun cu garda)
# In corpus si corpus2 ancorele NO sunt traduse (minte-inima / hjerte), deci
# perechea se face pe pozitie.  Capitolele doar-NO (rolul Norvegiei, ancora
# norge...) se sar; orice alta diferenta de numar e PROBLEMA in L1.
awk -F'\t' -f "$SCRIPT_DIR/harta.awk" "$W/cap" > "$W/harta"
grep '^MAP' "$W/harta" | cut -f2- > "$W/map"

# ════════════════════════════════════════════════════════════════════
titlu L1 "Ancorele capitolelor: fiecare capitol se poate lega direct"
# ════════════════════════════════════════════════════════════════════
awk -F'\t' '
  FILENAME == ARGV[1] { if ($1 == "NEPOTRIVIT") print "PROBLEMA " $2 ": " $3 " capitole RO, " $4 " NO — nu se pot pune fata in fata (doar capitolele norge... pot lipsi din RO)"
                        if ($1 == "DOARNO") dn = dn " " $2 "#" $4
                        next }
  { k = $1 "\t" $2
    if ($4 == "") print "PROBLEMA " $1 " (" $2 ") capitolul " $3 " fara ancora: „" substr($5, 1, 50) "”"
    else if ((k "\t" $4) in vazut) print "PROBLEMA " $1 " (" $2 ") ancora #" $4 " de doua ori"
    vazut[k "\t" $4] = 1
    if ($2 == "ro") tot++ }
  END { print "TOTAL " tot; print "DOARNO" dn }' "$W/harta" "$W/cap" > "$W/l1"
grep '^PROBLEMA' "$W/l1" | sort | while IFS= read -r l; do echo "  $l"; done
np=$(grep -c '^PROBLEMA' "$W/l1")
probleme=$((probleme + np))
tot=$(sed -n 's/^TOTAL //p' "$W/l1")
dn=$(sed -n 's/^DOARNO //p' "$W/l1")
[ "$np" -eq 0 ] && ok "$tot capitole RO, toate cu ancora unica, fiecare cu perechea lui NO"
[ -n "$dn" ] && ok "capitole doar in NO (rolul Norvegiei), sarite la potrivire: $dn"

# ════════════════════════════════════════════════════════════════════
titlu L2 "O singura casa pe tema: teme.tsv"
# ════════════════════════════════════════════════════════════════════
awk -F'\t' 'FILENAME == ARGV[1] { if ($2 == "ro") { doc[$1] = 1; anc[$1 "\tro\t" $4] = 1; poz[$1 "\t" $4] = $3 } next }
  FILENAME == ARGV[2] { arenno[$1 "\t" $2] = 1; next }
  /^#/ || /^[ \t]*$/ { next }
  { if (NF != 5) { print "PROBLEMA teme.tsv rand " FNR ": " NF " coloane in loc de 5"; next }
    if ($1 !~ /^[a-z0-9-]+$/) print "PROBLEMA teme.tsv rand " FNR ": id „" $1 "” (doar litere mici, cifre, -)"
    if ($1 in id) print "PROBLEMA teme.tsv: id „" $1 "” de doua ori"
    id[$1] = 1
    for (i = 2; i <= 5; i++) if ($i == "") print "PROBLEMA teme.tsv " $1 ": coloana " i " goala"
    c = $4; a = ""; j = index(c, "#"); if (j > 0) { a = substr(c, j + 1); c = substr(c, 1, j - 1) }
    if (!(c in doc)) { print "PROBLEMA teme.tsv " $1 ": casa „" $4 "” — documentul nu e in documente.tsv"; next }
    if (a != "" && !((c "\tro\t" a) in anc)) print "PROBLEMA teme.tsv " $1 ": casa „" $4 "” — ancora nu e a unui capitol din fisierul RO"
    else if (a != "" && !((c "\t" poz[c "\t" a]) in arenno)) print "PROBLEMA teme.tsv " $1 ": casa „" $4 "” — capitolul nu are pereche in NO"
    n++ }
  END { print "TOTAL " n+0 }' "$W/cap" "$W/map" "$TEME" > "$W/l2"
grep '^PROBLEMA' "$W/l2" | while IFS= read -r l; do echo "  $l"; done
np=$(grep -c '^PROBLEMA' "$W/l2")
probleme=$((probleme + np))
nteme=$(sed -n 's/^TOTAL //p' "$W/l2")
[ "$np" -eq 0 ] && ok "$nteme teme, fiecare cu o singura casa, care exista in RO si NO"
if [ "$np" -gt 0 ]; then
  echo ""; echo "  REZULTAT: teme.tsv are probleme — L3-L7 nu pot rula."; exit 1
fi

# temele, fara comentarii: id titlu_ro titlu_no casa_doc casa_anc tipar
awk -F'\t' '/^#/ || /^[ \t]*$/ { next }
  { c = $4; a = ""; j = index(c, "#"); if (j > 0) { a = substr(c, j + 1); c = substr(c, 1, j - 1) }
    print $1 "\t" $2 "\t" $3 "\t" c "\t" a "\t" $5 }' "$TEME" > "$W/teme"

# apartenenta: tema doc pos aparitii — numarate in textul RO al fiecarui capitol
awk -F'\t' '
  function numara(   k, c, n) {
    if (cur == "") return
    for (k = 1; k <= nt; k++) { c = text; n = gsub(tip[k], "&", c); if (n > 0) print tid[k] "\t" cd "\t" cp "\t" n }
  }
  FILENAME == ARGV[1] { nt++; tid[nt] = $1; tip[nt] = $6; next }
  FNR == 1 { numara(); cur = FILENAME; text = ""
             nume = FILENAME; sub(/.*\//, "", nume)
             cp = nume; sub(/.*\./, "", cp)
             cd = nume; sub(/\.ro\.[0-9]+$/, "", cd) }
  { text = text " " $0 }
  END { numara() }' "$W/teme" "$W"/t/*.ro.* > "$W/memb"

# capitolele care trateaza tema, in afara casei: tema doc pos n anc  (ordinea din manifest)
awk -F'\t' -v prag="$PRAG" '
  FILENAME == ARGV[1] { cd[$1] = $4; ca[$1] = $5; next }
  FILENAME == ARGV[2] { if ($2 == "ro") { ord[$1 "\t" $3] = ++o; an[$1 "\t" $3] = $4 } next }
  $4 + 0 >= prag {
    k = $2 "\t" $3
    if ($2 == cd[$1] && (ca[$1] == "" || ca[$1] == an[k])) next
    printf "%s\t%06d\t%s\t%s\t%s\t%s\n", $1, ord[k], $2, $3, $4, an[k] }' \
  "$W/teme" "$W/cap" "$W/memb" | sort -t "$(printf '\t')" -k1,1 -k2,2 | cut -f1,3- > "$W/apart"

# ════════════════════════════════════════════════════════════════════
titlu L3 "Legaturi lipsa: capitole care trateaza o tema fara sa trimita spre casa ei"
# ════════════════════════════════════════════════════════════════════
awk -F'\t' '
  FILENAME == ARGV[1] { cd[$1] = $4; ca[$1] = $5; ord[++nt] = $1; next }
  FILENAME == ARGV[2] { if ($2 == "ro") { k = $1 "\t" $3 "\t" $4; are[k] = 1; if ($6 != "") are[k "#" $6] = 1 } next }
  { t = $1; tinta = $2 "\t" $3 "\t" cd[t]
    ok = (ca[t] == "") ? (tinta in are) : ((tinta "#" ca[t]) in are)
    tot[t]++
    if (!ok) { lip[t]++; l[t] = l[t] " " $2 "#" $5 "(" $4 ")" } }
  END { for (i = 1; i <= nt; i++) { t = ord[i]
          if (tot[t] + 0 == 0) continue
          if (lip[t] + 0 == 0) { bune++; continue }
          print t ": " lip[t] " din " tot[t] " fara trimitere —" l[t]; s += lip[t] }
        print "TOTAL " s + 0 " " bune + 0 }' "$W/teme" "$W/trim" "$W/apart" > "$W/l3"
set -- $(sed -n 's/^TOTAL //p' "$W/l3")
grep -v '^TOTAL' "$W/l3" > "$W/l3b"
if [ "$1" -eq 0 ]; then ok "fiecare capitol care trateaza o tema trimite spre casa ei"
elif [ "$GARDA" = 1 ]; then
  atentie "$1 capitole trateaza o tema fara sa trimita spre casa ei — pe teme:$(awk '{ t = $1; sub(/:$/, "", t); printf "%s %s %s", (NR > 1 ? "," : ""), t, $2 }' "$W/l3b") (lista: sh scripts/legaturi.sh)"
else atentie "$1 capitole trateaza o tema fara sa trimita spre casa ei (tema: capitol(aparitii)) — de legat, tema cu tema:"; lista "$W/l3b"; fi

# ════════════════════════════════════════════════════════════════════
titlu L4 "Faptele: aceeasi cifra in casa si in alt capitol, fara id comun"
# ════════════════════════════════════════════════════════════════════
# Cifra = numar cu separator (43.000, 3,5), procent de cel putin doua cifre (38%)
# sau numar de cel putin 5 cifre.  2% sau 5% apar peste tot — zgomot, nu fapt.
# In capitolul din afara casei se cauta doar in textul NEMARCAT: cifrele marcate
# cu data-afirmatie sunt deja urmarite de garda [13].
cat > "$W/cifre.awk" <<'EOF'
function cifre(s, dest,   t) {
  while (match(s, /[0-9][0-9.,]*[0-9]%?|[0-9]%/)) {
    t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    if (t ~ /[0-9][0-9]%$/ || t ~ /[0-9][.,][0-9]/ || t ~ /^[0-9][0-9][0-9][0-9][0-9]/) dest[t] = 1
  }
}
{ cifre($0, casa) }
END { while ((getline l < eu) > 0) cifre(l, aici)
      for (c in aici) if (c in casa) v[++n] = c
      for (i = 2; i <= n; i++) { x = v[i]; for (j = i - 1; j > 0 && v[j] > x; j--) v[j + 1] = v[j]; v[j + 1] = x }
      for (i = 1; i <= n; i++) s = s " " v[i]
      if (n) print t ": " cap " —" s }
EOF
: > "$W/l4"
while IFS="$(printf '\t')" read -r t doc pos n anc; do
  hd=$(awk -F'\t' -v t="$t" '$1 == t { print $4 }' "$W/teme")
  ha=$(awk -F'\t' -v t="$t" '$1 == t { print $5 }' "$W/teme")
  if [ -n "$ha" ]; then
    hp=$(awk -F'\t' -v d="$hd" -v a="$ha" '$1 == d && $2 == "ro" && $4 == a { print $3 }' "$W/cap")
    set -- "$W/t/$hd.ro.$hp"
  else
    set -- "$W"/t/"$hd".ro.*
  fi
  awk -v eu="$W/u/$doc.ro.$pos" -v t="$t" -v cap="$doc#$anc" -f "$W/cifre.awk" "$@" >> "$W/l4" || exit 2
done < "$W/apart"
n4=$(grep -c . "$W/l4")
if [ "$n4" -eq 0 ]; then ok "nicio cifra nemarcata repetata intre casa unei teme si capitolele care o trateaza"
else atentie "$n4 capitole repeta, nemarcat, cifre din casa temei — de verificat: acelasi fapt? atunci acelasi id de afirmatie sau o trimitere:"; lista "$W/l4"; fi

# ════════════════════════════════════════════════════════════════════
titlu L5 "Paritatea RO-NO a trimiterilor spre capitole din alte documente"
# ════════════════════════════════════════════════════════════════════
# sursa si tinta aduse la pozitia RO a capitolului (ancorele NO pot fi traduse)
awk -F'\t' '
  FILENAME == ARGV[1] { rp[$1 "\tro\t" $4] = $3; next }
  FILENAME == ARGV[2] { npR[$1 "\t" $3] = $2; nanR[$1 "\t" $4] = $2; next }
  $4 != "-" && $4 != $1 && $6 != "" {
    if ($2 == "ro") { sp = $3 } else { if (!(($1 "\t" $3) in npR)) next; sp = npR[$1 "\t" $3] }
    if ($5 == "ro") tk = (($4 "\tro\t" $6) in rp) ? $4 "@" rp[$4 "\tro\t" $6] : $4 "#" $6
    else tk = (($4 "\t" $6) in nanR) ? $4 "@" nanR[$4 "\t" $6] : $4 "#" $6
    k = $1 "\t" sp "\t" tk; c[k "\t" $2]++; t[k] = 1 }
  END { for (k in t) if (c[k "\tro"] != c[k "\tno"]) {
          split(k, x, "\t"); print x[1] " capitolul " x[2] " -> " x[3] ": RO " c[k "\tro"] + 0 ", NO " c[k "\tno"] + 0 }
        for (k in t) n++; print "TOTAL " n + 0 }' "$W/cap" "$W/map" "$W/trim" > "$W/l5"
grep -v '^TOTAL' "$W/l5" | sort > "$W/l5b"
n5=$(sed -n 's/^TOTAL //p' "$W/l5")
if [ -s "$W/l5b" ]; then
  while IFS= read -r l; do problema "trimitere doar intr-o limba: $l"; done < "$W/l5b"
else ok "$n5 trimiteri spre capitole din alte documente, toate si in RO si in NO"; fi

# ════════════════════════════════════════════════════════════════════
titlu L6 "Orfanii: capitole fara tema si fara trimiteri; case fara vizitatori"
# ════════════════════════════════════════════════════════════════════
awk -F'\t' -v prag="$PRAG" '
  FILENAME == ARGV[1] { if ($4 + 0 >= prag) areT[$2 "\t" $3] = 1; next }
  FILENAME == ARGV[2] { cd[$1] = $4; ca[$1] = $5; ord[++nt] = $1; next }
  FILENAME == ARGV[3] { if ($2 == "ro" && $4 != "-" && $4 != $1) { primit[$4 "#" $6] = 1; primitD[$4] = 1 } next }
  $2 == "ro" { k = $1 "\t" $3
    if (!(k in areT) && !(($1 "#" $4) in primit)) { n++; pe[$1]++ }
    if (!($1 in vd)) { vd[$1] = 1; ordd[++nd] = $1 } }
  END { for (i = 1; i <= nd; i++) if (pe[ordd[i]]) s = s " " ordd[i] "(" pe[ordd[i]] ")"
        print "ORFANI " n + 0 "\t" s
        for (i = 1; i <= nt; i++) { t = ord[i]
          if (ca[t] != "" && !((cd[t] "#" ca[t]) in primit)) c = c " " t
          else if (ca[t] == "" && !(cd[t] in primitD)) c = c " " t }
        print "CASE " c }' "$W/memb" "$W/teme" "$W/trim" "$W/cap" > "$W/l6"
orf=$(sed -n 's/^ORFANI //p' "$W/l6")
case_=$(sed -n 's/^CASE //p' "$W/l6")
norf=${orf%%"$(printf '\t')"*}
if [ "$norf" -eq 0 ]; then ok "fiecare capitol are o tema sau primeste o trimitere"
else atentie "$norf capitole fara nicio tema din teme.tsv si fara nicio trimitere primita — pe documente:"
  echo "            ${orf#*"$(printf '\t')"}"; fi
if [ -z "$case_" ]; then ok "spre casa fiecarei teme trimite cel putin un alt document"
else atentie "case de tema spre care nu trimite, din text, niciun alt document (teme.html nu se socoteste):"
  echo "            $case_"; fi

# ════════════════════════════════════════════════════════════════════
titlu L7 "Pagina teme.html == ce se genereaza acum din teme.tsv"
# ════════════════════════════════════════════════════════════════════
awk -F'\t' -v base="$BASE" -v hub="$HUBNAME" -v prag="$PRAG" '
  function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); gsub(/"/, "\\&quot;", s); return s }
  function scurt(s,   p, n) {
    n = split(s, p, / — | – | · /)
    if (p[1] == "România" || p[1] == "Romania") { s = p[1] " — " p[2]; sub(/\. .*/, "", s); return s }
    return p[1]
  }
  function url(d, lg, a,   r, c) {
    r = repo[d]; c = (lg == "ro") ? ro[d] : no[d]
    if (r == hub) u = base "/" c
    else if (c == "index.html") u = base "/" r "/"
    else u = base "/" r "/" c
    return (a != "") ? u "#" a : u
  }
  function leg(d, a, b) { return "<a href=\"" url(d, "ro", a) "\">RO</a> · <a href=\"" url(d, "no", b) "\">NO</a>" }
  FILENAME == ARGV[1] { if ($0 ~ /^#/ || NF < 7) next
                        repo[$1] = $3; ro[$1] = $4; no[$1] = $5; tro[$1] = scurt($6); tno[$1] = scurt($7); next }
  FILENAME == ARGV[2] { ttl[$1 "\t" $2 "\t" $3] = $5; pa[$1 "\t" $2 "\t" $4] = $3; next }
  FILENAME == ARGV[3] { nan[$1 "\t" $2] = $4; npo[$1 "\t" $2] = $3; next }
  FILENAME == ARGV[4] { nt++; id[nt] = $1; tr[nt] = $2; tn[nt] = $3; cd[nt] = $4; ca[nt] = $5; next }
  { m[$1] = m[$1] "\n" $2 "\t" $3 "\t" $5 }
  END {
    print "<!DOCTYPE html>"
    print "<html lang=\"ro\">"
    print "<head>"
    print "<meta charset=\"UTF-8\">"
    print "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">"
    print "<title>Index tematic · Temaregister — norgedan</title>"
    print "<meta name=\"description\" content=\"Temele care străbat documentele norgedan, fiecare cu o singură casă și cu capitolele în care mai apare. · Temaene som går gjennom norgedan-dokumentene, hvert med ett hjem.\">"
    print "<link rel=\"canonical\" href=\"" base "/teme.html\">"
    print "<style>"
    print ":root{--bg:#0d0f14;--fg:#e8e6e1;--muted:#9a978f;--gold:#d4a843;--line:#2a2d36;}"
    print "body{margin:0;background:var(--bg);color:var(--fg);font-family:Georgia,\"Times New Roman\",serif;line-height:1.6;}"
    print "main{max-width:820px;margin:0 auto;padding:1rem 1.2rem 3rem;}"
    print "a{color:var(--gold);}"
    print ".nd-nav-sus{max-width:820px;margin:0 auto;padding:.8rem 1.2rem 0;font-size:.85rem;}"
    print "h1{color:var(--gold);font-size:1.7rem;margin:1.2rem 0 .3rem;}"
    print ".sub{color:var(--muted);font-size:.95rem;margin:0 0 2rem;}"
    print ".tema{border:1px dashed rgba(212,168,67,.45);border-radius:6px;padding:1rem 1.2rem;margin:0 0 1.2rem;}"
    print ".tema h2{color:var(--gold);font-size:1.15rem;margin:0 0 .5rem;}"
    print ".casa{margin:.2rem 0 .7rem;}"
    print ".et{color:var(--muted);font-size:.85rem;display:block;}"
    print "ol{margin:.3rem 0 0;padding-left:1.3rem;}"
    print "li{margin:.25rem 0;}"
    print ".no{color:var(--muted);font-size:.85rem;display:block;}"
    print ".gen{color:var(--muted);font-size:.8rem;margin-top:2rem;border-top:1px solid var(--line);padding-top:1rem;}"
    print "</style>"
    print "</head>"
    print "<body>"
    print "<nav class=\"nd-nav-sus\"><a href=\"" base "/\">← norgedan · pagina principală · forsiden</a></nav>"
    print "<main>"
    print "<h1>Index tematic · Temaregister</h1>"
    print "<p class=\"sub\">Fiecare temă are o singură casă: capitolul sau documentul unde e tratată pe larg și ținută la zi. Dedesubt, celelalte capitole în care apare. · Hvert tema har ett hjem: kapitlet eller dokumentet der det behandles grundig og holdes oppdatert. Nedenfor de andre kapitlene der det dukker opp.</p>"
    for (i = 1; i <= nt; i++) {
      d = cd[i]; a = ca[i]
      print "<section class=\"tema\" id=\"" id[i] "\">"
      print "<h2>" esc(tr[i]) " · " esc(tn[i]) "</h2>"
      if (a != "") {
        p = pa[d "\tro\t" a]
        cas = esc(tro[d]) " — " esc(ttl[d "\tro\t" p]) " " leg(d, a, nan[d "\t" p]) "<span class=\"no\">" esc(tno[d]) " — " esc(ttl[d "\tno\t" npo[d "\t" p]]) "</span>"
      } else cas = esc(tro[d]) " (tot documentul · hele dokumentet) " leg(d, "", "") "<span class=\"no\">" esc(tno[d]) "</span>"
      print "<p class=\"casa\"><span class=\"et\">Casa temei · Temaets hjem</span>" cas "</p>"
      if (m[id[i]] != "") {
        print "<span class=\"et\">Apare și în · Finnes også i</span>"
        print "<ol>"
        k = split(substr(m[id[i]], 2), r, "\n")
        for (j = 1; j <= k; j++) { split(r[j], f, "\t")
          q = f[1] "\t" f[2]
          print "<li>" esc(tro[f[1]]) " — " esc(ttl[f[1] "\tro\t" f[2]]) " " leg(f[1], f[3], nan[q]) "<span class=\"no\">" esc(tno[f[1]]) " — " esc(ttl[f[1] "\tno\t" npo[q]]) "</span></li>" }
        print "</ol>"
      }
      print "</section>"
    }
    print "<p class=\"gen\">Pagină generată de scripts/legaturi.sh din scripts/teme.tsv. Un capitol e trecut la o temă dacă tiparul ei revine de cel puțin " prag " ori în textul lui. · Siden er generert av scripts/legaturi.sh fra scripts/teme.tsv. Et kapittel føres opp under et tema hvis temaets mønster forekommer minst " prag " ganger i teksten.</p>"
    print "</main>"
    print "</body>"
    print "</html>"
  }' "$MAN" "$W/cap" "$W/map" "$W/teme" "$W/apart" > "$W/index.html"

if [ "$MOD" = scrie ]; then
  cp "$W/index.html" "$INDEX" || exit 2
  ok "teme.html rescris din teme.tsv ($nteme teme).  Citeste diferenta inainte de commit:"
  echo "             git -C $HUB diff --stat"
elif [ ! -f "$INDEX" ]; then
  problema "lipseste teme.html — sh $0 --scrie"
elif cmp -s "$W/index.html" "$INDEX"; then
  ok "teme.html e la zi ($nteme teme)"
else
  problema "teme.html nu mai corespunde teme.tsv sau capitolelor de acum — sh $0 --scrie, apoi git diff"
fi

# ════════════════════════════════════════════════════════════════════
titlu L8 "Cifrele RO-NO: acelasi capitol, aceleasi numere in ambele limbi"
# ════════════════════════════════════════════════════════════════════
# pas122.  NO e traducerea lui RO: un numar care apare intr-o limba si lipseste din
# cealalta e o posibila greseala de traducere (34 din 240 de erori gasite pana acum).
# Filtre, ca sa ramana doar diferentele adevarate:
#   - separatorul de mii: 43.000 (RO) = 43 000 (NO) = 43000; procentul fara „%”
#   - trimiterile la versete (3:16, 3:5,8, 22:1-5): editiile difera prin numerotare
#   - psalmii numiti fara verset (Psalmul 103 / Salme 104): numerotarea LXX / ebraica
#   - anul editiilor: 1688 (Biblia de la Bucuresti) nu se numara; „Bibelen 1930” nici
#     atat — NO de obicei nu numeste editia langa verset, RO da
#   - secolele si deceniile: NO scrie „1400-tallet”, „1990-årene”, RO „secolul al
#     XV-lea”, „anii '90” / „anii 1990” — se scot din ambele; la fel „det 21. århundre”
#     (RO: „secolul XXI”, cu cifre romane)
#   - intervalul de ani scurtat: 1946–47 = 1946–1947
#   - numerele de o singura cifra: se scriu des in cuvinte („trei” / „tre”)
# ATENTIE, nu PROBLEMA: o diferenta poate fi legitima — de citit capitol cu capitol.
cat > "$W/l8.awk" <<'EOF'
# 1946-47 -> 1946-1947: doar cand anul scurtat urmeaza imediat dupa liniuta (pas122b;
# in pas122 regula privea orice numar de doua cifre de dupa „2026-”, si „2026-utgaven
# ... pa 31. plass” devenea 2031)
function interval(s,   o, a) {
  o = ""
  while (match(s, /(1[0-9]|20)[0-9][0-9]-[0-9][0-9]/)) {
    if (substr(s, RSTART + RLENGTH, 1) ~ /[0-9]/ || (RSTART > 1 && substr(s, RSTART - 1, 1) ~ /[0-9]/)) {
      o = o substr(s, 1, RSTART + RLENGTH - 1); s = substr(s, RSTART + RLENGTH); continue }
    a = substr(s, RSTART, RLENGTH)
    o = o substr(s, 1, RSTART - 1) substr(a, 1, 5) substr(a, 1, 2) substr(a, 6, 2)
    s = substr(s, RSTART + RLENGTH)
  }
  return o s
}
function norm(s, lg) {
  gsub("\302\240", " ", s); gsub("\342\200\223", "-", s); gsub("\342\200\224", "-", s)
  if (lg == "no") { gsub(/[0-9]+-(tallet|årene|tallets)/, " ", s); gsub(/Bibel(en)? (fra )?1930|1930-(bibelen|oversettelsen)/, " ", s)
                    gsub(/[0-9]+\. (århundre|årtusen)/, " ", s) }
  else gsub(/anii '?[0-9]+/, " ", s)
  gsub(/[0-9]+:[0-9]+([-,][0-9]+)*/, " ", s)
  s = interval(s)
  gsub(/Psalm[a-z]* [0-9]+/, " ", s); gsub(/Salm[a-z]* [0-9]+/, " ", s); gsub(/Sal [0-9]+/, " ", s)
  return s
}
function cifre(f, lg, dest,   l, s, t) {
  s = ""
  while ((getline l < f) > 0) s = s " " l
  close(f); s = norm(s, lg)
  while (match(s, /[0-9]+([. ][0-9][0-9][0-9])*(,[0-9]+)?/)) {
    t = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
    gsub(/[. ]/, "", t)
    if (t ~ /^[0-9]$/ || t == "1688") continue
    dest[t] = 1
  }
}
$1 == "MAP" {
  split("", r); split("", n)
  cifre(dir "/" $2 ".ro." $3, "ro", r); cifre(dir "/" $2 ".no." $4, "no", n)
  if (("1688" in r) && ("1930" in n) && !("1688" in n) && !("1930" in r)) { delete r["1688"]; delete n["1930"] }
  dr = ""; dn = ""
  for (c in r) if (!(c in n)) dr = dr " " c
  for (c in n) if (!(c in r)) dn = dn " " c
  if (dr != "" || dn != "") print $2 "#" $6 "\t" dr "\t" dn
  tot++
}
END { print "TOTAL\t" tot + 0 }
EOF
awk -F'\t' -v dir="$W/t" -f "$W/l8.awk" "$W/harta" > "$W/l8"
n8=$(grep -c -v '^TOTAL' "$W/l8")
t8=$(awk -F'\t' '$1 == "TOTAL" { print $2 }' "$W/l8")   # pas122b: nu sed '\t' (GNU)
# fiecare lista sortata, ca iesirea sa nu depinda de ordinea interna a lui awk
grep -v '^TOTAL' "$W/l8" | awk -F'\t' '
  function srt(s,   a, n, i, j, x, o) { n = split(s, a, " ")
    for (i = 2; i <= n; i++) { x = a[i]; for (j = i - 1; j > 0 && (a[j] + 0 > x + 0 || (a[j] + 0 == x + 0 && a[j] > x)); j--) a[j + 1] = a[j]; a[j + 1] = x }
    o = ""; for (i = 1; i <= n; i++) o = o " " a[i]; return o }
  { r = srt($2); no = srt($3)
    printf "%s —%s%s\n", $1, (r != "" ? " doar RO:" r : ""), (no != "" ? (r != "" ? ";" : "") " doar NO:" no : "") }' > "$W/l8b"
if [ "$n8" -eq 0 ]; then ok "$t8 perechi de capitole, aceleasi numere in RO si NO"
else atentie "$n8 din $t8 perechi de capitole au numere doar intr-o limba — de citit: traducere gresita sau diferenta legitima?"; lista "$W/l8b"; fi

# ════════════════════════════════════════════════════════════════════
titlu L9 "Randurile de tema: doar legaturi spre casele din teme.tsv"
# ════════════════════════════════════════════════════════════════════
# pas123.  Forma singura admisa, intr-un capitol, pe un rand:
#   RO  <p class="nd-tema">Tema: <a href="...casa...">Moldova</a> · <a ...>China</a></p>
#   NO  <p class="nd-tema">Tema: <a href="...hjem...">Moldova</a></p>
# Garda [18] scoate randul din amprenta capitolului (e navigare, nu afirmatie); de aceea
# aici e PROBLEMA orice altceva: alt text decat „Tema:” / „Teme:” / „Temaer:” si „·”,
# alt tag decat <a>, atribute in plus, legatura spre altceva decat casa unei teme in
# aceeasi limba, textul legaturii diferit de titlul temei, teme diferite in RO si NO,
# sau un rand nd-tema in afara textului capitolelor (comentariu, aside, nav).
awk -F'\t' '
  FILENAME == ARGV[1] { nt++; tid[nt] = $1; tro[nt] = $2; tno[nt] = $3; cd[nt] = $4; ca[nt] = $5; next }
  FILENAME == ARGV[2] { r2n[$1 "\t" $2] = $4; n2r[$1 "\t" $3] = $2; rp[$1 "\t" $5] = $2; next }
  FILENAME == ARGV[3] { site[$5] = $1 "\t" $2; next }
  { d = $1; lg = $2; ps = $3; loc = d " (" lg ") capitolul " ps
    nr++
    if ($4 != "-") print "PROBLEMA " loc ": randul de tema are " $4
    rest = $5; gsub("\302\267", "", rest); gsub(/ /, "", rest)
    if (rest !~ /^(Tema|Teme|Temaer):$/) print "PROBLEMA " loc ": text in afara legaturilor: „" $5 "” (admis: Tema: si ·)"
    if (NF < 6) print "PROBLEMA " loc ": randul de tema nu are nicio legatura"
    k = (lg == "ro") ? ps : n2r[d "\t" ps]
    for (i = 6; i <= NF; i++) {
      nl++; j = index($i, "|"); tg = substr($i, 1, j - 1); tx = substr($i, j + 1); gsub(/^ +| +$/, "", tx)
      jj = index(tg, ">"); pth = substr(tg, 1, jj - 1); anc = substr(tg, jj + 1)
      if (!(pth in site)) { print "PROBLEMA " loc ": legatura „" tx "” nu duce la un document (" tg ")"; continue }
      split(site[pth], z, "\t")
      if (z[2] != lg) { print "PROBLEMA " loc ": legatura „" tx "” duce in alta limba (" z[2] ")"; continue }
      g = 0
      for (q = 1; q <= nt; q++) {
        if (cd[q] != z[1]) continue
        if (ca[q] == "") ok = (anc == "")
        else ok = (lg == "ro") ? (anc == ca[q]) : (anc == r2n[z[1] "\t" rp[z[1] "\t" ca[q]]])
        if (ok) { g = q; break }
      }
      if (!g) { print "PROBLEMA " loc ": legatura „" tx "” nu duce la casa unei teme din teme.tsv (" z[1] "#" anc ")"; continue }
      tt = (lg == "ro") ? tro[g] : tno[g]
      if (tx != tt) print "PROBLEMA " loc ": textul legaturii „" tx "” nu e titlul temei „" tt "”"
      tem[d "\t" k "\t" lg] = tem[d "\t" k "\t" lg] " " tid[g]; ck[d "\t" k] = 1
    }
  }
  END {
    for (c in ck) if (tem[c "\tro"] != tem[c "\tno"]) { split(c, x, "\t")
      print "PROBLEMA " x[1] " capitolul " x[2] ": teme diferite in RO (" tem[c "\tro"] " ) si NO (" tem[c "\tno"] " )" }
    print "TOTAL " nr + 0 " " nl + 0 }' "$W/teme" "$W/map" "$W/f" "$W/nt" > "$W/l9"
# santinela: fiecare class="nd-tema" din fisier trebuie sa fi fost citit, in text de capitol
while IFS="$(printf '\t')" read -r doc lang repo cale site; do
  b=$(grep -o 'class="nd-tema"' "$RADACINA/$repo/$cale" | wc -l | tr -d ' ')
  v=$(awk -F'\t' -v d="$doc" -v l="$lang" '$1 == d && $2 == l' "$W/nt" | wc -l | tr -d ' ')
  [ "$b" -ne "$v" ] && echo "PROBLEMA $doc ($lang): $b randuri nd-tema in fisier, $v citite in textul capitolelor — unul sta intr-un comentariu, aside, nav sau in afara capitolelor"
done < "$W/f" >> "$W/l9"
grep '^PROBLEMA' "$W/l9" | sort > "$W/l9p"
while IFS= read -r l; do problema "${l#PROBLEMA }"; done < "$W/l9p"   # nu „| while”: contorul s-ar pierde
set -- $(sed -n 's/^TOTAL //p' "$W/l9")
if ! grep -q '^PROBLEMA' "$W/l9"; then
  if [ "$1" -eq 0 ]; then ok "niciun rand de tema inca"
  else ok "$1 randuri de tema, $2 legaturi — toate spre casele din teme.tsv, aceleasi teme in RO si NO"; fi
fi

if [ "$GARDA" != 1 ]; then
  echo ""
  echo "===================================================="
  if [ "$probleme" -eq 0 ]; then echo "  REZULTAT: nicio problema (ATENTIE = lucru de facut, nu greseala)."
  else echo "  REZULTAT: $probleme probleme."; fi
  echo "===================================================="
fi
[ "$probleme" -eq 0 ]
