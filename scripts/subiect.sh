#!/bin/sh
# subiect.sh — indexul de subiecte: tot ce spune site-ul despre un subiect, intr-o lista (pas147).
#
# Primul pas al remodelarii hotarate pe 12 nov. 2026: corpusurile sa vorbeasca aceeasi
# limba.  Scriptul doar CITESTE: nu schimba nicio pagina si niciun registru, nu face
# parte din garda si nu opreste niciun push.
#
#   sh ~/norgedan.github.io/scripts/subiect.sh            toate subiectele, pe scurt
#   sh ~/norgedan.github.io/scripts/subiect.sh <id>       fisa unui subiect
#   sh ~/norgedan.github.io/scripts/subiect.sh --fara     capitolele fara niciun subiect declarat
#
# Subiect = un rand din teme.tsv (subiect cu casa) sau din subiecte.tsv (fara casa inca).
# Ce subiecte trateaza un capitol e DECLARAT in capitole-subiecte.tsv (pas148): un subiect
# principal si, daca e cazul, cateva secundare — stabilite prin citire, aprobate de Bogdan.
# Tiparul subiectului e doar ALARMA: fisa arata unde tiparul si registrul se contrazic
# (tiparul de cel putin PRAG ori intr-un capitol care nu declara subiectul; subiect
# declarat intr-un capitol in care tiparul nu apare deloc).
# O afirmatie tine de subiect daca tiparul e in textul ei marcat (RO) sau in randul ei
# din afirmatii.tsv (acolo fara diacritice) — inca pe cuvinte, nu declarat.
#
# Limite, spuse: randurile „provizoriu” din registru sunt puse dupa titlu si tipare, nu
# dupa citire; faptele nemarcate nu apar la afirmatii.
#
# POSIX: sh (ksh pe OpenBSD), awk (one-true-awk), sort, mktemp.  LC_ALL=C.

LC_ALL=C; export LC_ALL
PRAG=3
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 2
HUB=$(dirname "$SCRIPT_DIR")
RADACINA=$(dirname "$HUB")
MAN="$SCRIPT_DIR/documente.tsv"
TEME="$SCRIPT_DIR/teme.tsv"
SUB="$SCRIPT_DIR/subiecte.tsv"
AFI="$SCRIPT_DIR/afirmatii.tsv"
CAPV="$SCRIPT_DIR/capitole-verificate.tsv"
REG="$SCRIPT_DIR/capitole-subiecte.tsv"

CE=${1:-}
case "$CE" in
  -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
  --fara|"") ;;
  -*) echo "utilizare: sh $0 [<id> | --fara]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "utilizare: sh $0 [<id> | --fara]" >&2; exit 2; }
for f in "$MAN" "$TEME" "$SUB" "$AFI" "$CAPV" "$REG" "$SCRIPT_DIR/capitole.awk"; do
  [ -f "$f" ] || { echo "lipseste $f" >&2; exit 2; }
done

W=$(mktemp -d "${TMPDIR:-/tmp}/subiect.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
trap 'exit 2' INT TERM HUP
mkdir "$W/t" "$W/u"

# ── subiectele: id titlu_ro casa tipar ───────────────────────────────
awk -F'\t' '
  /^#/ || /^[ \t]*$/ { next }
  NF != 5 { print "subiect.sh: " FILENAME " rand " FNR ": " NF " coloane in loc de 5" > "/dev/stderr"; rau = 1; next }
  $1 !~ /^[a-z0-9-]+$/ { print "subiect.sh: " FILENAME " rand " FNR ": id „" $1 "”" > "/dev/stderr"; rau = 1; next }
  $1 in v { print "subiect.sh: id „" $1 "” de doua ori (teme.tsv si subiecte.tsv)" > "/dev/stderr"; rau = 1; next }
  { v[$1] = 1; print $1 "\t" $2 "\t" $4 "\t" $5 }
  END { exit rau }' "$TEME" "$SUB" > "$W/s" || exit 2

if [ -n "$CE" ] && [ "$CE" != --fara ]; then
  cut -f1 "$W/s" | grep -qx -- "$CE" || {
    echo "subiect necunoscut: $CE" >&2; echo "subiectele: $(cut -f1 "$W/s" | tr '\n' ' ')" >&2; exit 2; }
fi

# ── capitolele RO si textul lor (cititorul comun, capitole.awk) ──────
awk -F'\t' '/^#/ || NF < 7 { next } { print $1 "\t" $3 "\t" $4 }' "$MAN" > "$W/f"
: > "$W/cap"
while IFS="$(printf '\t')" read -r doc repo cale; do
  fis="$RADACINA/$repo/$cale"
  [ -f "$fis" ] || { echo "lipseste $fis" >&2; exit 2; }
  awk -v doc="$doc" -v lang=ro -v site="$cale" -v base=https://norgedan.github.io \
      -v tdir="$W/t" -v udir="$W/u" -v lnk="$W/lnk" -v capf="$W/cap" -v ntf="$W/nt" \
      -f "$SCRIPT_DIR/capitole.awk" "$fis" || exit 2
  # afirmatiile marcate: doc id text (fara tag-uri), una pe rand
  awk -v doc="$doc" '
    { s = s " " $0 }
    END { while (match(s, /<span data-afirmatie="[^"]*">/)) {
            id = substr(s, RSTART + 22, RLENGTH - 24); s = substr(s, RSTART + RLENGTH)
            j = index(s, "</span>"); t = (j > 0) ? substr(s, 1, j - 1) : ""
            gsub(/<[^>]*>/, "", t); gsub(/[ \t\r]+/, " ", t)
            print doc "\t" id "\t" t } }' "$fis" >> "$W/af"
done < "$W/f"
: >> "$W/af"

# ── potrivirea: subiect x capitol, subiect x afirmatie ───────────────
# sc: subiect doc poz ancora aparitii titlu      sa: subiect id doc
awk -F'\t' -v tdir="$W/t" -v sc="$W/sc" -v sa="$W/sa" '
  FILENAME == ARGV[1] { id[++n] = $1; pat[n] = $4; next }
  FILENAME == ARGV[2] { if (!/^#/) reg[$1] = $4; next }
  FILENAME == ARGV[3] { f = tdir "/" $1 ".ro." $3; x = ""
                        while ((getline l < f) > 0) x = x " " l
                        close(f)
                        for (i = 1; i <= n; i++) { y = x; k = gsub(pat[i], "&", y)
                          if (k > 0) print id[i] "\t" $1 "\t" $3 "\t" $4 "\t" k "\t" $5 > sc }
                        next }
  { for (i = 1; i <= n; i++) if ($3 ~ pat[i] || reg[$2] ~ pat[i]) print id[i] "\t" $2 "\t" $1 > sa }' \
  "$W/s" "$AFI" "$W/cap" "$W/af"
: >> "$W/sc"; : >> "$W/sa"
sort -u "$W/sa" > "$W/sa2"

TOT=$(wc -l < "$W/cap" | tr -d ' ')

# ── registrul declarat: verificat, apoi  dc: subiect doc ancora rol(P|S) cum ──
awk -F'\t' -v dc="$W/dc" '
  FILENAME == ARGV[1] { sub_[$1] = 1; next }
  FILENAME == ARGV[2] { cap[$1 "\t" $4] = 1; next }
  /^#/ || /^[ \t]*$/ { next }
  { k = $1 "\t" $2
    if (NF != 5) { print "subiect.sh: capitole-subiecte.tsv rand " FNR ": " NF " coloane in loc de 5" > "/dev/stderr"; rau = 1; next }
    if (!(k in cap)) { print "subiect.sh: capitole-subiecte.tsv: " $1 "#" $2 " nu e un capitol RO" > "/dev/stderr"; rau = 1; next }
    if (k in v) { print "subiect.sh: capitole-subiecte.tsv: " $1 "#" $2 " de doua ori" > "/dev/stderr"; rau = 1; next }
    v[k] = 1
    if ($5 != "citit" && $5 != "provizoriu") { print "subiect.sh: capitole-subiecte.tsv " $1 "#" $2 ": „" $5 "” (citit | provizoriu)" > "/dev/stderr"; rau = 1 }
    if ($3 != "-") { if ($3 in sub_) print $3 "\t" k "\tP\t" $5 > dc
                     else { print "subiect.sh: capitole-subiecte.tsv " $1 "#" $2 ": subiect necunoscut „" $3 "”" > "/dev/stderr"; rau = 1 } }
    if ($4 != "-") { n = split($4, a, " ")
      for (i = 1; i <= n; i++) { if (a[i] in sub_) print a[i] "\t" k "\tS\t" $5 > dc
        else { print "subiect.sh: capitole-subiecte.tsv " $1 "#" $2 ": subiect necunoscut „" a[i] "”" > "/dev/stderr"; rau = 1 } } } }
  END { for (k in cap) if (!(k in v)) { split(k, b, "\t"); print "subiect.sh: capitole-subiecte.tsv: lipseste capitolul " b[1] "#" b[2] > "/dev/stderr"; rau = 1 }
        exit rau }' "$W/s" "$W/cap" "$REG" || exit 2
: >> "$W/dc"

# alarmele:  al: subiect fel(T = tipar fara declaratie | D = declarat fara tipar) doc ancora aparitii
awk -F'\t' -v prag="$PRAG" '
  FILENAME == ARGV[1] { d[$1 "\t" $2 "\t" $3] = 1; next }
  FILENAME == ARGV[2] { k = $1 "\t" $2 "\t" $4; n[k] = $5
                        if ($5 + 0 >= prag && !(k in d)) print $1 "\tT\t" $2 "\t" $4 "\t" $5; next }
  END { for (k in d) if (!(k in n)) { split(k, b, "\t"); print b[1] "\tD\t" b[2] "\t" b[3] "\t0" } }' \
  "$W/dc" "$W/sc" "$W/dc" | sort > "$W/al"

PROV=$(grep -v '^#' "$REG" | awk -F'\t' '$5 == "provizoriu"' | wc -l | tr -d ' ')

# ── capitolele fara niciun subiect declarat ──────────────────────────
awk -F'\t' 'FILENAME == ARGV[1] { are[$2 "\t" $3] = 1; next }
  FILENAME == ARGV[2] { if (!/^#/) cum[$1 "\t" $2] = $5; next }
  !(($1 "\t" $4) in are) { print $1 "#" $4 "\t" $5 "\t" cum[$1 "\t" $4] }' "$W/dc" "$REG" "$W/cap" > "$W/fara"
NF_=$(wc -l < "$W/fara" | tr -d ' ')

if [ "$CE" = --fara ]; then
  echo "Capitole RO fara niciun subiect declarat in capitole-subiecte.tsv: $NF_ din $TOT"
  echo "  (sinteza = citit si lasat fara subiect: deschidere sau concluzie; de lamurit = inca necitit)"
  awk -F'\t' 'function scurt(t, m) { if (length(t) <= m) return t; t = substr(t, 1, m); sub(/ [^ ]*$/, "", t); return t " ..." }
    { printf "  %-32s %-11s %s\n", $1, ($3 == "citit" ? "sinteza" : "de lamurit"), scurt($2, 52) }' "$W/fara"
  echo ""
  echo "Randuri inca „provizoriu” (puse dupa titlu si tipare, necitite intreg): $PROV din $TOT"
  exit 0
fi

# ── toate subiectele, pe scurt ───────────────────────────────────────
if [ -z "$CE" ]; then
  echo "Subiectele norgedan (teme.tsv + subiecte.tsv; capitolele: capitole-subiecte.tsv)"
  echo "  subiect                  principal  secundar  afirmatii  alarme  primul termen  casa"
  awk -F'\t' '
    FILENAME == ARGV[1] { if ($4 == "P") pr[$1]++; else se[$1]++; next }
    FILENAME == ARGV[2] { al[$1]++; next }
    FILENAME == ARGV[3] { if (!/^#/ && $8 ~ /^20/) rv[$1] = $8; next }
    FILENAME == ARGV[4] { if (!(($1 "\t" $2) in v)) { v[$1 "\t" $2] = 1; na[$1]++
                            if (($2 in rv) && (t[$1] == "" || rv[$2] < t[$1])) t[$1] = rv[$2] } next }
    { printf "  %-24s %9d %9d %10d %7d  %-13s  %s\n", $1, pr[$1], se[$1], na[$1], al[$1], (t[$1] == "" ? "-" : t[$1]), $3 }' \
    "$W/dc" "$W/al" "$AFI" "$W/sa2" "$W/s"
  echo ""
  echo "  $NF_ din $TOT capitole RO fara niciun subiect declarat (lista: sh $0 --fara)"
  echo "  $PROV din $TOT randuri din registru sunt inca „provizoriu”"
  echo "  fisa unui subiect: sh $0 <id>"
  exit 0
fi

# ── fisa unui subiect ────────────────────────────────────────────────
IFS="$(printf '\t')" read -r sid stitlu scasa spat <<EOT
$(grep "^$CE	" "$W/s")
EOT
echo "===================================================="
echo "  SUBIECT: $sid — $stitlu"
if [ "$scasa" = "-" ]; then echo "  casa: inca niciuna (subiecte.tsv)"; else echo "  casa: $scasa (teme.tsv)"; fi
echo "===================================================="

grep "^$CE	" "$W/sc" > "$W/c1"
grep "^$CE	" "$W/dc" > "$W/d1"
for rol in P S; do
  awk -F'\t' -v rol="$rol" 'function scurt(t, m) { if (length(t) <= m) return t; t = substr(t, 1, m); sub(/ [^ ]*$/, "", t); return t " ..." }
    FILENAME == ARGV[1] { if (!/^#/) v[$1 "\t" $2] = $4; next }
    FILENAME == ARGV[2] { n[$2 "\t" $4] = $5; next }
    FILENAME == ARGV[3] { ti[$1 "\t" $4] = $5; ord[$1 "\t" $4] = ++q; next }
    $4 == rol { k = $2 "\t" $3
      printf "%05d\t  %-30s %3d aparitii   %-22s %-10s %s\n", ord[k], $2 "#" $3, n[k], ((k in v) ? "verificat (" v[k] ")" : "NEVERIFICAT intreg"), $5, scurt(ti[k], 40) }' \
    "$CAPV" "$W/c1" "$W/cap" "$W/d1" | sort | cut -f2- > "$W/o$rol"
done
echo ""
echo "Subiect principal in: $(wc -l < "$W/oP" | tr -d ' ') capitole"
cat "$W/oP"
echo ""
echo "Subiect secundar in: $(wc -l < "$W/oS" | tr -d ' ') capitole"
cat "$W/oS"

grep "^$CE	T	" "$W/al" > "$W/a_t"; grep "^$CE	D	" "$W/al" > "$W/a_d"
echo ""
echo "Alarma — tiparul de cel putin $PRAG ori, dar subiectul nu e declarat: $(wc -l < "$W/a_t" | tr -d ' ')"
awk -F'\t' '{ printf "  %s(%d)", $3 "#" $4, $5; n++; if (n % 4 == 0) printf "\n" } END { if (n % 4) printf "\n" }' "$W/a_t"
echo "Alarma — subiect declarat, dar tiparul nu apare deloc: $(wc -l < "$W/a_d" | tr -d ' ')"
awk -F'\t' '{ printf "  %s", $3 "#" $4; n++; if (n % 4 == 0) printf "\n" } END { if (n % 4) printf "\n" }' "$W/a_d"

awk -F'\t' -v prag="$PRAG" 'FILENAME == ARGV[1] { d[$2 "\t" $3] = 1; next }
  $5 + 0 < prag && !(($2 "\t" $4) in d) { printf "  %s(%d)", $2 "#" $4, $5; n++; if (n % 4 == 0) printf "\n" } END { if (n % 4) printf "\n" }' "$W/d1" "$W/c1" > "$W/o2"
echo ""
echo "Doar pomenit (tiparul de 1-$((PRAG - 1)) ori, nedeclarat): $(tr -s ' \n' '\n\n' < "$W/o2" | grep -c '#')"
cat "$W/o2"

grep "^$CE	" "$W/sa2" > "$W/a1"
awk -F'\t' 'FILENAME == ARGV[1] { if (!/^#/) { et[$1] = $2; rv[$1] = $8 } next }
  { if (!($2 in d)) ord[++n] = $2; d[$2] = d[$2] " " $3; nd[$2]++ }
  END { for (i = 1; i <= n; i++) { a = ord[i]
          printf "%s\t%s\t%s\t%d\t%s\n", (rv[a] ~ /^20/ ? rv[a] : "9999"), a, (a in et ? et[a] : "?"), nd[a], d[a] } }' \
  "$AFI" "$W/a1" | sort > "$W/a2"
n3=$(wc -l < "$W/a2" | tr -d ' ')
n4=$(awk -F'\t' '$4 > 1' "$W/a2" | wc -l | tr -d ' ')
echo ""
echo "Afirmatii marcate care tin de subiect: $n3 (dintre care $n4 in mai multe documente)"
echo "  reverificare   afirmatie                   eticheta       documente"
awk -F'\t' '{ printf "  %-13s  %-27s %-13s %s\n", ($1 == "9999" ? "-" : $1), $2, $3, $5 }' "$W/a2"

t1=$(awk -F'\t' '$1 != "9999" { print $1 " (" $2 ")"; exit }' "$W/a2")
echo ""
echo "Primul termen de reverificare: ${t1:--}"
echo "Limita: randurile „provizoriu” nu sunt inca citite intreg; afirmatiile, inca pe cuvinte."
