#!/bin/sh
# subiect.sh — indexul de subiecte: tot ce spune site-ul despre un subiect, intr-o lista (pas147).
#
# Primul pas al remodelarii hotarate pe 12 nov. 2026: corpusurile sa vorbeasca aceeasi
# limba.  Scriptul doar CITESTE: nu schimba nicio pagina si niciun registru, nu face
# parte din garda si nu opreste niciun push.
#
#   sh ~/norgedan.github.io/scripts/subiect.sh            toate subiectele, pe scurt
#   sh ~/norgedan.github.io/scripts/subiect.sh <id>       fisa unui subiect
#   sh ~/norgedan.github.io/scripts/subiect.sh --fara     capitolele fara niciun subiect
#
# Subiect = un rand din teme.tsv (subiect cu casa) sau din subiecte.tsv (fara casa inca).
# Un capitol TRATEAZA subiectul daca tiparul revine de cel putin PRAG ori in textul lui
# RO (acelasi prag ca in legaturi.sh); sub prag, il POMENESTE.  O afirmatie tine de
# subiect daca tiparul e in textul ei marcat (RO) sau in randul ei din afirmatii.tsv
# (acolo fara diacritice: un tipar scris doar cu diacritice nu o prinde).
#
# Limite, spuse: potrivirea e pe cuvinte, nu pe inteles — un capitol poate vorbi despre
# subiect fara niciun cuvant din tipar, si invers; faptele nemarcate nu apar la afirmatii.
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

CE=${1:-}
case "$CE" in
  -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  --fara|"") ;;
  -*) echo "utilizare: sh $0 [<id> | --fara]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "utilizare: sh $0 [<id> | --fara]" >&2; exit 2; }
for f in "$MAN" "$TEME" "$SUB" "$AFI" "$CAPV" "$SCRIPT_DIR/capitole.awk"; do
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

# ── capitolele fara niciun subiect ───────────────────────────────────
awk -F'\t' -v prag="$PRAG" 'FILENAME == ARGV[1] { if ($5 + 0 >= prag) are[$2 "\t" $3] = 1; next }
  !(($1 "\t" $3) in are) { print $1 "#" $4 "\t" $5 }' "$W/sc" "$W/cap" > "$W/fara"
NF_=$(wc -l < "$W/fara" | tr -d ' ')

if [ "$CE" = --fara ]; then
  echo "Capitole RO care nu trateaza niciun subiect (tiparul sub $PRAG aparitii): $NF_ din $TOT"
  awk -F'\t' 'function scurt(t, m) { if (length(t) <= m) return t; t = substr(t, 1, m); sub(/ [^ ]*$/, "", t); return t " ..." }
    { printf "  %-32s %s\n", $1, scurt($2, 60) }' "$W/fara"
  exit 0
fi

# ── toate subiectele, pe scurt ───────────────────────────────────────
if [ -z "$CE" ]; then
  echo "Subiectele norgedan (teme.tsv + subiecte.tsv)"
  echo "  subiect           capitole: trateaza / pomenesc   afirmatii   primul termen   casa"
  awk -F'\t' -v prag="$PRAG" '
    FILENAME == ARGV[1] { if ($5 + 0 >= prag) tr[$1]++; else po[$1]++; next }
    FILENAME == ARGV[2] { if (!/^#/ && $8 ~ /^20/) rv[$1] = $8; next }
    FILENAME == ARGV[3] { if (!(($1 "\t" $2) in v)) { v[$1 "\t" $2] = 1; na[$1]++
                            if (($2 in rv) && (t[$1] == "" || rv[$2] < t[$1])) t[$1] = rv[$2] } next }
    { printf "  %-17s %9d / %-18d %6d      %-13s   %s\n", $1, tr[$1], po[$1], na[$1], (t[$1] == "" ? "-" : t[$1]), $3 }' \
    "$W/sc" "$AFI" "$W/sa2" "$W/s"
  echo ""
  echo "  $NF_ din $TOT capitole RO nu trateaza niciun subiect (lista: sh $0 --fara)"
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
awk -F'\t' -v prag="$PRAG" 'function scurt(t, m) { if (length(t) <= m) return t; t = substr(t, 1, m); sub(/ [^ ]*$/, "", t); return t " ..." }
  FILENAME == ARGV[1] { if (!/^#/) v[$1 "\t" $2] = $4; next }
  $5 + 0 >= prag { k = $2 "\t" $4
    printf "  %-30s %3d aparitii   %-22s %s\n", $2 "#" $4, $5, ((k in v) ? "verificat (" v[k] ")" : "NEVERIFICAT intreg"), scurt($6, 46) }' \
  "$CAPV" "$W/c1" > "$W/o1"
n1=$(wc -l < "$W/o1" | tr -d ' ')
echo ""
echo "Capitole care trateaza subiectul (tiparul de cel putin $PRAG ori): $n1"
cat "$W/o1"

awk -F'\t' -v prag="$PRAG" '$5 + 0 < prag { printf "  %s(%d)", $2 "#" $4, $5; n++; if (n % 4 == 0) printf "\n" } END { if (n % 4) printf "\n" }' "$W/c1" > "$W/o2"
n2=$(awk -F'\t' -v prag="$PRAG" '$5 + 0 < prag' "$W/c1" | wc -l | tr -d ' ')
echo ""
echo "Capitole care doar il pomenesc (1-$((PRAG - 1)) aparitii): $n2"
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
echo "Limita: potrivire pe cuvinte, nu pe inteles; faptele nemarcate nu apar la afirmatii."
