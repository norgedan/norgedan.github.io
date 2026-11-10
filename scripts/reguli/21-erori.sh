#!/bin/sh
# 21-erori.sh — regula [21] a garzii norgedan: erorile gasite si corectate, pe tipuri.
# Mutata din verifica-site.sh in pas138 (pilotul „fiecare regula un script”), neschimbata.
#
# Din pas67.  scripts/erori.tsv — o eroare gasita si corectata = un rand (TAB):
#   pas  id  ancora  tip  descriere  sursa
#   tip: superlativ | atribuire | cifra | cronologie | atenuare | traducere | contradictie | alta
#   ancora: numele capitolului RO (ca in capitole-verificate.tsv, din pas128; pana atunci
#           pozitia <h2>) sau "-";  sursa: https://... sau "-"
# Nu blocheaza decat un rand stricat; altfel numara erorile pe tipuri.
# pas128: ancora trebuie sa existe in documentul randului (lista din [18], capanc); o
# pozitie numerica nu mai e primita — un capitol inserat mai sus ar muta-o in tacere.
#
# Chemare:  sh 21-erori.sh <scripts> <pregatire>
# Din pregatire citeste:  m (manifestul plat, din [1]) si capanc (ancorele, din [18]).
SCRIPT_DIR=$1; W=$2
[ -d "$SCRIPT_DIR" ] && [ -d "$W" ] || { echo "utilizare: sh $0 <scripts> <pregatire>" >&2; exit 2; }
ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; }

ERORI="$SCRIPT_DIR/erori.tsv"
if [ ! -f "$ERORI" ]; then
  problema "lipseste scripts/erori.tsv"
else
  grep -v '^#' "$ERORI" | grep -v '^[[:space:]]*$' > "$W/r21.er"
  # santinela: fara lista ancorelor din [18], verificarea ancorelor n-ar vedea nimic
  [ -s "$W/capanc" ] || problema "[21] lista ancorelor capitolelor (din [18]) e goala — ancorele din erori.tsv nu pot fi verificate"
  awk -F'\t' -v MF="$W/m" -v AF="$W/capanc" '
    BEGIN { while ((getline l < MF) > 0) { split(l, x, "\t"); doc[x[1]] = 1 }
            while ((getline l < AF) > 0) { split(l, x, "\t"); anc[x[1] "\t" x[3]] = 1 } }
    NF != 6 { print "erori.tsv rand " NR ": " NF " coloane, trebuie 6"; next }
    $1 !~ /^pas[0-9]+[a-z]?$/ { print "erori.tsv rand " NR ": pas \"" $1 "\"" }
    !($2 in doc) { print "erori.tsv rand " NR ": \"" $2 "\" nu e in manifest" }
    $3 ~ /^[0-9]+$/ { print "erori.tsv rand " NR ": pozitia \"" $3 "\" — din pas128 capitolul se numeste prin ancora (ca in capitole-verificate.tsv)"; next }
    $3 != "-" && ($2 in doc) && !(($2 "\t" $3) in anc) { print "erori.tsv rand " NR ": ancora \"" $3 "\" nu e un capitol RO din " $2 }
    $4 !~ /^(superlativ|atribuire|cifra|cronologie|atenuare|traducere|contradictie|alta)$/ { print "erori.tsv rand " NR ": tip \"" $4 "\"" }
    $5 ~ /^[[:space:]]*-?[[:space:]]*$/ { print "erori.tsv rand " NR ": fara descriere" }
    $6 != "-" && $6 !~ /^https:\/\// { print "erori.tsv rand " NR ": sursa \"" $6 "\" — https://... sau -" }
  ' "$W/r21.er" > "$W/r21.err" || exit 3
  if [ -s "$W/r21.err" ]; then
    while IFS= read -r l; do problema "$l"; done < "$W/r21.err"
  else
    ok "$(wc -l < "$W/r21.er" | tr -d ' ') erori gasite si corectate, pe tipuri: $(cut -f4 "$W/r21.er" | LC_ALL=C sort | uniq -c | sort -rn | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')"
  fi
fi
exit 0
