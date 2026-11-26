#!/bin/sh
# texte.sh — faptul scris o singura data (pasul 2 al remodelarii, pas153).
#
# scripts/texte.tsv tine textul fiecarei afirmatii inscrise, in cel mult doua forme
# (intreg, scurt) si doua limbi.  Scriptul compara paginile cu registrul si, la cerere,
# pune in pagini textul din registru — identic in fiecare loc.
#
#   sh ~/norgedan.github.io/scripts/texte.sh            doar CITESTE: arata unde pagina si
#                                                       registrul nu spun acelasi lucru
#   sh ~/norgedan.github.io/scripts/texte.sh --scrie    pune textul din registru in pagini
#   sh ~/norgedan.github.io/scripts/texte.sh <id>       arata formele unei afirmatii si locurile lor
#
# Ce verifica, pentru fiecare id din texte.tsv:
#   - cel mult o forma „intreg” si una „scurt” pe limba;
#   - fiecare fisier din rand exista si are marcajul <span data-afirmatie="id"> o singura data;
#   - textul din marcaj e cel din registru (spatiile unificate);
#   - nicio alta pagina nu poarta acelasi id fara sa fie trecuta in registru.
#
# Dupa --scrie urmeaza, ca la orice schimbare de text marcat: verifica-site.sh --amprente
# (afirmatia a fost reverificata la sursa), --capitole unde e cazul, dovezi.sh --scrie, garda.
#
# Din pas154 garda il ruleaza in [13]: o diferenta sau o problema opreste push-ul.
# Iesire: 0 = paginile spun ce spune registrul; 1 = diferente sau registru gresit; 2 = utilizare.
# POSIX: sh (ksh pe OpenBSD), awk (one-true-awk), find, grep, mktemp, cmp, cp.  LC_ALL=C.
# Marcajul il citeste scripts/marcaje.awk (pas196), ca in dovezi.sh.

LC_ALL=C; export LC_ALL
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 2
HUB=$(dirname "$SCRIPT_DIR")
RADACINA=${RADACINA:-$(dirname "$HUB")}      # garda si testele o dau din afara (ca la dovezi.sh)
TEXTE="$SCRIPT_DIR/texte.tsv"
REPOURI="norgedan.github.io corpus corpus2 opera limba limba-ro-final"

MOD=citeste; UNUL=
case ${1:-} in
  '')       ;;
  --scrie)  MOD=scrie ;;
  -*)       echo "utilizare: sh $0 [--scrie | <id>]" >&2; exit 2 ;;
  *)        MOD=arata; UNUL=$1 ;;
esac
[ $# -le 1 ] || { echo "utilizare: sh $0 [--scrie | <id>]" >&2; exit 2; }
[ -f "$TEXTE" ] || { echo "PROBLEMA lipseste scripts/texte.tsv" >&2; exit 1; }

W=$(mktemp -d /tmp/texte.XXXXXX) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

# 1. registrul: forma lui
awk -F'\t' '
  /^#/ || /^$/ { next }
  NF != 5 { printf "PROBLEMA texte.tsv randul %d: %d coloane, trebuie 5\n", NR, NF; rau = 1; next }
  $2 != "intreg" && $2 != "scurt" { printf "PROBLEMA texte.tsv randul %d: forma „%s” (intreg | scurt)\n", NR, $2; rau = 1 }
  $3 != "ro" && $3 != "no" { printf "PROBLEMA texte.tsv randul %d: limba „%s” (ro | no)\n", NR, $3; rau = 1 }
  $4 == "" || $5 == "" { printf "PROBLEMA texte.tsv randul %d: coloana goala\n", NR; rau = 1 }
  index($5, "<span") || index($5, "</span>") { printf "PROBLEMA texte.tsv randul %d: textul contine un <span>\n", NR; rau = 1 }
  (($1, $2, $3) in vazut) { printf "PROBLEMA texte.tsv randul %d: %s are deja forma %s in %s\n", NR, $1, $2, $3; rau = 1 }
  { vazut[$1, $2, $3] = 1 }
  $4 != "-" { n = split($4, f, " "); for (i = 1; i <= n; i++) {
      if ((($1), f[i]) in loc) { printf "PROBLEMA texte.tsv randul %d: %s e trecut de doua ori pentru %s\n", NR, f[i], $1; rau = 1 }
      loc[$1, f[i]] = 1
      if (f[i] !~ ("-" $3 "\\.html$")) { printf "PROBLEMA texte.tsv randul %d: %s nu e o pagina in limba „%s”\n", NR, f[i], $3; rau = 1 } } }
  END { exit rau }' "$TEXTE" || exit 1

if [ -n "$UNUL" ]; then
  awk -F'\t' -v id="$UNUL" '
    /^#/ || $1 != id { next }
    { g = 1; printf "\n%s — forma %s, %s (%d caractere)\n  %s\n  in: %s\n", $1, $2, $3, length($5), $5, $4 }
    END { if (!g) { printf "Niciun rand pentru „%s” in texte.tsv.\n", id; exit 1 } }' "$TEXTE"
  exit $?
fi

# 2. fiecare (id, fisier): pagina fata de registru; la --scrie, pagina noua in $W.
# Din pas196, marcajul il gaseste cititorul comun, scripts/marcaje.awk (aceeasi definitie
# ca in dovezi.sh): forma exacta, in afara comentariilor HTML.
[ -s "$SCRIPT_DIR/marcaje.awk" ] || { echo "PROBLEMA lipseste scripts/marcaje.awk (cititorul marcajelor)" >&2; exit 1; }
cat > "$W/pag.awk" <<'AWK'
function unifica(s) { gsub(/[ \t\r\n]+/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s); return s }
FNR == NR { if ($0 !~ /^#/) { split($0, c, "\t"); if (c[1] == id && c[2] == forma && index(" " c[4] " ", " " fis " ")) text = c[5] } next }
{ pag = pag $0 "\n" }
END {
  marcaje(pag); g = 0
  for (k = 1; k <= MK_N; k++) if (MK_ID[k] == id) { g++; if (g == 1) u = k }
  if (!g) { print "PROBLEMA\t" id "\t" fis "\tmarcajul lipseste din pagina"; exit }
  if (g > 1) { print "PROBLEMA\t" id "\t" fis "\tmarcajul apare de mai multe ori"; exit }
  if (!MK_E[u]) { print "PROBLEMA\t" id "\t" fis "\tmarcajul nu se inchide"; exit }
  if (MK_IMB[u]) { print "PROBLEMA\t" id "\t" fis "\tun <span> in interiorul marcajului"; exit }
  acum = substr(pag, MK_B[u], MK_E[u] - MK_B[u])
  if (unifica(acum) == unifica(text)) { print "LAFEL\t" id "\t" fis "\t" forma; exit }
  print "ALTFEL\t" id "\t" fis "\t" forma
  print "    pagina:    " unifica(acum)
  print "    registrul: " unifica(text)
  printf "%s%s%s", substr(pag, 1, MK_B[u] - 1), text, substr(pag, MK_E[u]) > iesire
}
AWK
: > "$W/rezultat"; N=0
awk -F'\t' '!/^#/ && NF == 5 && $4 != "-" { n = split($4, f, " "); for (i = 1; i <= n; i++) print $1 "\t" $2 "\t" f[i] }' "$TEXTE" > "$W/perechi"

while IFS='	' read -r ID FORMA FIS; do
  P="$RADACINA/$FIS"
  if [ ! -f "$P" ]; then echo "PROBLEMA	$ID	$FIS	fisierul lipseste" >> "$W/rezultat"; continue; fi
  N=$((N + 1))
  awk -v id="$ID" -v fis="$FIS" -v forma="$FORMA" -v iesire="$W/nou.$N" -f "$SCRIPT_DIR/marcaje.awk" -f "$W/pag.awk" "$TEXTE" "$P" >> "$W/rezultat"
  if [ "$MOD" = scrie ] && [ -s "$W/nou.$N" ]; then
    cp "$W/nou.$N" "$P" || { echo "PROBLEMA	$ID	$FIS	nu s-a putut scrie" >> "$W/rezultat"; }
  fi
done < "$W/perechi"

# 3. pagini care poarta un id inscris, dar nu sunt in registru
awk -F'\t' '!/^#/ && NF == 5 { print $1 }' "$TEXTE" | sort -u > "$W/iduri"
for R in $REPOURI; do
  [ -d "$RADACINA/$R" ] || continue
  find "$RADACINA/$R" -name .git -prune -o -type f -name '*.html' -print
done | sort > "$W/pagini"
while read -r ID; do
  while read -r P; do
    grep -q "data-afirmatie=\"$ID\"" "$P" || continue
    FIS=${P#"$RADACINA"/}
    grep -q "^$ID	[a-z]*	$FIS\$" "$W/perechi" || echo "PROBLEMA	$ID	$FIS	pagina poarta marcajul, dar nu e trecuta in texte.tsv" >> "$W/rezultat"
  done < "$W/pagini"
done < "$W/iduri"

NL=$(grep -c '^LAFEL' "$W/rezultat"); NA=$(grep -c '^ALTFEL' "$W/rezultat"); NP=$(grep -c '^PROBLEMA' "$W/rezultat")
NI=$(wc -l < "$W/iduri" | tr -d ' ')
grep -v '^LAFEL' "$W/rezultat" | awk -F'\t' '
  $1 == "ALTFEL"   { printf "  ALTFEL    %-20s %s (forma %s)\n", $2, $3, $4; next }
  $1 == "PROBLEMA" { printf "  PROBLEMA  %-20s %s — %s\n", $2, $3, $4; next }
  { print }'
echo ""
echo "  texte.tsv: $NI afirmatii inscrise; $NL locuri la fel cu registrul, $NA altfel, $NP probleme."
if [ "$MOD" = scrie ]; then
  [ "$NA" -gt 0 ] && echo "  Scris: $NA locuri au acum textul din registru.  Urmeaza: --amprente, --capitole (unde e cazul), dovezi.sh --scrie, garda."
  [ "$NP" -eq 0 ] || exit 1
  exit 0
fi
[ "$NA" -eq 0 ] && [ "$NP" -eq 0 ] || exit 1
exit 0
