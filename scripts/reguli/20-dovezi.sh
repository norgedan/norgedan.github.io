#!/bin/sh
# 20-dovezi.sh — regula [20] a garzii norgedan: dovezile afirmatiilor (surse.tsv).
# Mutata din verifica-site.sh in pas143 („fiecare regula un script”), cu logica neschimbata.
#
# Din pas67.  „verificat” in afirmatii.tsv e o declaratie.  Aici sta dovada:
#   scripts/surse.tsv — un rand = o sursa citita pentru o afirmatie (TAB):
#     id  nivel  url  accesat  cine  citat
#   nivel   P = primara (institutia care masoara, documentul oficial, studiul original)
#           S = secundara serioasa (agentie, presa de referinta)
#           T = tertiara (blog, agregator, enciclopedie) — nu ajunge niciodata singura
#   accesat AAAA-LL-ZZ — ziua in care sursa a fost citita
#   cine    cine a citit sursa: „claude” sau numele omului (litere mici).  Limita
#           spusa deschis: o afirmatie citita doar de Claude n-a vazut ochi
#           independenti; raportul le numara separat.
#   citat   textul exact din sursa, intre « », sau "-".  Exact = copiat din pagina,
#           nu din rezumatul unui instrument: altfel "-".
# Regula: FAPT verificat = cel putin o sursa P, sau doua S din domenii diferite.
#         ESTIMARE verificata = cel putin o sursa P sau S.  INTERPRETARE si CREDINTA:
#         sursele sunt binevenite, nu obligatorii.
#   scripts/surse-datorie.txt — afirmatiile mai vechi decat registrul de surse (pas67),
#   inca fara dovezi; lista doar scade.  O afirmatie noua, fara surse, blocheaza.
#
# Chemare:  sh 20-dovezi.sh <scripts> <pregatire>
# Din pregatire citeste:  af (afirmatiile, din [13]).  Scrie:  r20.sr (randurile din
# surse.tsv fara comentarii), r20.sd, r20.err, r20.p.
SCRIPT_DIR=$1; W=$2
[ -d "$SCRIPT_DIR" ] && [ -d "$W" ] || { echo "utilizare: sh $0 <scripts> <pregatire>" >&2; exit 2; }
ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; }
atentie()  { echo "  ATENTIE  $1"; }
[ -s "$SCRIPT_DIR/lib.awk" ] || { echo "lipseste sau e goala biblioteca scripts/lib.awk" >&2; exit 3; }
LIB_AWK=$(cat "$SCRIPT_DIR/lib.awk")
# santinela: fara afirmatiile din [13], nicio sursa n-ar avea de cine sa se lege
[ -s "$W/af" ] || problema "[20] lista afirmatiilor (din [13]) e goala — dovezile nu pot fi judecate"

SURSE="$SCRIPT_DIR/surse.tsv"; SDAT="$SCRIPT_DIR/surse-datorie.txt"
if [ ! -f "$SURSE" ] || [ ! -f "$SDAT" ]; then
  problema "lipseste scripts/surse.tsv sau scripts/surse-datorie.txt"
else
  grep -v '^#' "$SURSE" | grep -v '^[[:space:]]*$' > "$W/r20.sr"
  grep -v '^#' "$SDAT" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u > "$W/r20.sd"
  AZI=$(date +%Y-%m-%d)
  awk -F'\t' -v AF="$W/af" -v SD="$W/r20.sd" -v AZI="$AZI" "$LIB_AWK"'
    # pas91: domeniul inregistrat (amp.cnn.com si edition.cnn.com = cnn.com), cu sufixele
    # de doua niveluri uzuale (co.uk, com.ua, gov.ua ...): aceeasi publicatie e o singura sursa
    function dom(u,  d, n, p, b) { d = tolower(u); sub(/^https:\/\//, "", d); sub(/[\/:?#].*/, "", d)
      n = split(d, p, "."); if (n < 2) return d; b = p[n - 1] "." p[n]
      if (n > 2 && length(p[n]) == 2 && p[n - 1] ~ /^(co|com|org|net|gov|ac|edu)$/) b = p[n - 2] "." b
      return b }
    BEGIN { while ((getline l < AF) > 0) { split(l, x, "\t"); et[x[1]] = x[2]; st[x[1]] = x[3] }
            while ((getline l < SD) > 0) dat[l] = 1 }
    NF != 6 { print "surse.tsv rand " NR ": " NF " coloane, trebuie 6"; next }
    { for (i = 1; i <= 6; i++) if ($i ~ /^[[:space:]]*$/) { print "surse.tsv rand " NR ": coloana " i " goala (se scrie -)"; next } }
    !($1 in et) { print "surse.tsv: \"" $1 "\" nu e in afirmatii.tsv"; next }
    $2 !~ /^[PST]$/ { print "surse.tsv " $1 ": nivel \"" $2 "\" — P, S sau T" }
    $3 !~ /^https:\/\/[^ ]+\.[^ ]+/ { print "surse.tsv " $1 ": adresa \"" $3 "\" — trebuie https://..." }
    !dataok($4) { print "surse.tsv " $1 ": accesat \"" $4 "\" — trebuie o data reala AAAA-LL-ZZ" }
    $4 > AZI { print "surse.tsv " $1 ": accesat " $4 " e in viitor" }
    $5 !~ /^[a-z][a-z-]*$/ { print "surse.tsv " $1 ": cine \"" $5 "\" — un nume, litere mici" }
    $6 != "-" && ($6 !~ /^«.*»$/ || split($6, w, " ") < 4) { print "surse.tsv " $1 ": citat — intre « », minim 4 cuvinte, sau -" }
    { n[$1]++; if ($2 == "P") p[$1]++; if ($2 == "S" && !((($1) SUBSEP dom($3)) in sd)) { sd[$1, dom($3)] = 1; s[$1]++ }
      if ($5 == "claude") cl[$1] = 1; else om[$1] = 1; if ($6 != "-") ct[$1] = 1 }
    END {
      for (i in et) {
        if (st[i] != "verificat") continue
        nevoie = (et[i] == "FAPT") ? "F" : (et[i] == "ESTIMARE") ? "E" : ""
        if (nevoie == "") continue
        ok = (nevoie == "F") ? (p[i] > 0 || s[i] >= 2) : (p[i] > 0 || s[i] > 0)
        if (i in dat) { if (ok) print "DATORIE-STINSA\t" i; continue }
        if (!(i in n)) print "afirmatia \"" i "\" (" et[i] ") nu are nicio sursa in surse.tsv si nu e in surse-datorie.txt"
        else if (!ok) print "afirmatia \"" i "\" (" et[i] "): dovezi insuficiente — " (nevoie == "F" ? "un FAPT cere o sursa P sau doua S din domenii diferite" : "o ESTIMARE cere o sursa P sau S")
      }
      for (i in dat) if (!(i in et)) print "surse-datorie.txt: \"" i "\" nu mai e in afirmatii.tsv — scoate-l"
      for (i in n) { N++; if (i in om) O++; else C++; if (!(i in ct)) X++ }
      printf "STAT\t%d\t%d\t%d\t%d\n", N, C, O, X
    }' "$W/r20.sr" > "$W/r20.err" || exit 3
  grep -v '^STAT	' "$W/r20.err" | grep -v '^DATORIE-STINSA	' > "$W/r20.p"
  if [ -s "$W/r20.p" ]; then
    while IFS= read -r l; do problema "$l"; done < "$W/r20.p"
  else
    set -- $(grep '^STAT	' "$W/r20.err" | cut -f2- | tr '\t' ' ')
    ok "$1 afirmatii cu dovezi in surse.tsv, toate cu sursa suficienta; citite doar de Claude: $2, si de un om: $3; fara citat exact: $4"
  fi
  grep '^DATORIE-STINSA	' "$W/r20.err" | cut -f2 | while IFS= read -r i; do atentie "surse-datorie.txt: \"$i\" are acum dovezi suficiente — scoate-l din datorie"; done
  nd=$(wc -l < "$W/r20.sd" | tr -d ' ')
  [ "$nd" -gt 0 ] && atentie "$nd afirmatii verificate inainte de pas67, inca fara dovezi in surse.tsv (datoria; scade, nu creste)"
fi
exit 0
