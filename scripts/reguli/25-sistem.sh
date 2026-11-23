#!/bin/sh
# 25-sistem.sh - regula [25] a garzii norgedan (pas182): sistemul se cunoaste pe sine.
# Auditul din 23 nov. 2026: paginile au inventarul lor ([2]), scripturile nu aveau niciunul.
#
# scripts/sistem.tsv e manifestul scripturilor (vezi antetul lui).  Regula cere:
#   PROBLEMA  un script de pe disc (scripts/*.sh, *.awk, *.py, reguli/*.sh, hooks/*) fara rand,
#             sau un rand fara script; un rand stricat (6 coloane, nimic gol)
#   PROBLEMA  un script care nu se numeste in primele 3 randuri (antetul spune cine e)
#   PROBLEMA  un registru numit in citeste/scrie care nu exista; un registru de pe disc
#             (scripts/*.tsv, *.txt, reguli/reguli.tsv) pe care nu-l citeste nimeni
#   PROBLEMA  un apelant care nu e in lista si nu e Bogdan, Claude sau CI; un apelant care
#             nu-l pomeneste deloc pe cel chemat (regulile din reguli.tsv le cheama garda
#             prin registru, nu prin nume)
#   ATENTIE   scripturile fara niciun test (coloana teste = nu)
# Limita, spusa: ce citeste si ce scrie un script e declarat, nu masurat; regula vede doar
# daca numele sunt reale, nu daca lista e completa.
#
# Chemare:  sh 25-sistem.sh <scripts> <pregatire>
# POSIX sh si awk.
SCRIPT_DIR=$1; W=$2
[ -d "$SCRIPT_DIR" ] && [ -d "$W" ] || { echo "utilizare: sh $0 <scripts> <pregatire>" >&2; exit 2; }
ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; }
atentie()  { echo "  ATENTIE  $1"; }

M="$SCRIPT_DIR/sistem.tsv"
if [ ! -s "$M" ]; then problema "lipseste scripts/sistem.tsv (manifestul scripturilor) sau e gol"; exit 0; fi
grep -v '^#' "$M" | grep -v '^[[:space:]]*$' > "$W/r25.m"
[ -s "$W/r25.m" ] || { problema "scripts/sistem.tsv nu are niciun rand — sistemul nu se cunoaste"; exit 0; }

# ce e pe disc
( cd "$SCRIPT_DIR" && for f in *.sh *.awk *.py reguli/*.sh hooks/*; do [ -f "$f" ] && echo "$f"; done ) | sort > "$W/r25.disc"
( cd "$SCRIPT_DIR" && for f in *.tsv *.txt reguli/reguli.tsv; do [ -f "$f" ] && echo "$f"; done ) | sort > "$W/r25.reg"
grep -v '^#' "$SCRIPT_DIR/reguli/reguli.tsv" 2>/dev/null | cut -f2 > "$W/r25.rg"
: > "$W/r25.p"; : > "$W/r25.nu"

awk -F'\t' -v DF="$W/r25.disc" -v RF="$W/r25.reg" -v GF="$W/r25.rg" -v P="$W/r25.p" -v NU="$W/r25.nu" '
  BEGIN { while ((getline l < DF) > 0) disc[l] = 1
          while ((getline l < RF) > 0) reg[l] = 1
          while ((getline l < GF) > 0) rg[l] = 1 }
  { if (NF != 6) { print "sistem.tsv, randul „" $1 "”: " NF " coloane in loc de 6" > P; next }
    for (i = 1; i <= 6; i++) if ($i == "") { print "sistem.tsv, randul „" $1 "”: coloana " i " goala (pune -)" > P; next }
    if ($1 in are) print "sistem.tsv: „" $1 "” de doua ori" > P
    are[$1] = 1
    if (!($1 in disc)) print "sistem.tsv: „" $1 "” nu exista pe disc (scripts/" $1 ")" > P
    for (c = 3; c <= 4; c++) { n = split($c, x, ",")
      for (j = 1; j <= n; j++) { if (x[j] == "-" || index(x[j], ":")) continue
        if (!(x[j] in reg)) print "sistem.tsv, „" $1 "”: registrul „" x[j] "” nu exista in scripts/" > P
        if (c == 3) citit[x[j]] = 1 } }
    n = split($5, x, ",")
    for (j = 1; j <= n; j++) { a = x[j]
      if (a == "Bogdan" || a == "Claude" || a == "CI") continue
      apel[$1 "\t" a] = 1 }
    if ($6 == "nu") print $1 > NU
    else if ($6 != "da" && $6 != "garda") print "sistem.tsv, „" $1 "”: teste = „" $6 "” (da, garda sau nu)" > P }
  END { for (d in disc) if (!(d in are)) print "scripts/" d " nu e in sistem.tsv — orice script spune cine e, ce citeste, ce scrie si cine il cheama" > P
        for (r in reg) if (!(r in citit)) print "registrul scripts/" r " nu e citit de niciun script din sistem.tsv — cine il foloseste?" > P
        for (k in apel) { split(k, y, "\t")
          if (!(y[2] in are)) { print "sistem.tsv, „" y[1] "”: apelantul „" y[2] "” nu e in lista (nici Bogdan, Claude, CI)" > P; continue }
          print k > (P ".apel") } }' "$W/r25.m" || { problema "[25] citirea lui sistem.tsv s-a oprit cu eroare (awk) — manifestul nu e verificat"; exit 0; }

# un apelant numit chiar il pomeneste pe cel chemat (numele fisierului, in textul apelantului)
if [ -f "$W/r25.p.apel" ]; then
  while IFS="$(printf '\t')" read -r cel cine; do
    b=$(basename "$cel")
    if grep -q -F "$b" "$SCRIPT_DIR/$cine" 2>/dev/null; then continue; fi
    if [ "$cine" = verifica-site.sh ] && grep -q -x -F "$cel" "$W/r25.rg"; then continue; fi
    echo "sistem.tsv, „$cel”: e trecut ca chemat de $cine, dar $cine nu-l pomeneste" >> "$W/r25.p"
  done < "$W/r25.p.apel"
fi
# fiecare script se numeste in primele 3 randuri
while IFS= read -r f; do
  head -n 3 "$SCRIPT_DIR/$f" | grep -q -F "$(basename "$f")" || echo "scripts/$f nu se numeste in primele 3 randuri — antetul spune cine e" >> "$W/r25.p"
done < "$W/r25.disc"

if [ -s "$W/r25.p" ]; then sort -u "$W/r25.p" | while IFS= read -r l; do problema "$l"; done
else ok "$(wc -l < "$W/r25.m" | tr -d ' ') scripturi in sistem.tsv, toate pe disc si toate numite in antet; $(wc -l < "$W/r25.reg" | tr -d ' ') registre, fiecare cu cel putin un cititor; apelantii il pomenesc pe cel chemat"; fi
if [ -s "$W/r25.nu" ]; then atentie "$(wc -l < "$W/r25.nu" | tr -d ' ') scripturi fara niciun test: $(sort "$W/r25.nu" | tr '\n' ' ' | sed 's/ $//')"; fi
