#!/bin/sh
# eveniment.sh — evenimentul si efectele lui (pasul 3 al remodelarii, pas155).  Doar CITESTE.
#
#   sh ~/norgedan.github.io/scripts/eveniment.sh                     lista evenimentelor
#   sh ~/norgedan.github.io/scripts/eveniment.sh <id>                fisa unui eveniment
#   sh ~/norgedan.github.io/scripts/eveniment.sh --subiect <subiect> evenimentele unui subiect:
#                                                                    ale lui si cele care ajung
#                                                                    la el dinspre alte subiecte
#
# Fisa arata: ce s-a intamplat; efectele — in bine, in rau, urmari — fiecare cu afirmatia
# (sursa), criteriul si starea (propus / aprobat); subiectele legate; ce e de adus la zi:
# paginile care poarta afirmatiile evenimentului si daca textul lor sta in texte.tsv.
#
# Registre: evenimente.tsv, efecte.tsv (aici), afirmatii.tsv, subiecte.tsv (registrul unic), texte.tsv.
# Nu face parte din garda si nu opreste niciun push.  Registrele gresite opresc scriptul.
# Iesire: 0 = bine; 1 = registru gresit sau id necunoscut; 2 = utilizare.
# POSIX: sh (ksh pe OpenBSD), awk, find, grep, sort, mktemp.  LC_ALL=C.

LC_ALL=C; export LC_ALL
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 2
HUB=$(dirname "$SCRIPT_DIR")
RADACINA=${RADACINA:-$(dirname "$HUB")}
EV="$SCRIPT_DIR/evenimente.tsv"; EF="$SCRIPT_DIR/efecte.tsv"
AF="$SCRIPT_DIR/afirmatii.tsv"; TX="$SCRIPT_DIR/texte.tsv"
REPOURI="norgedan.github.io corpus corpus2 opera limba limba-ro-final"

MOD=lista; CE=
case ${1:-} in
  '')         [ $# -eq 0 ] || { echo "utilizare: sh $0 [<id> | --subiect <subiect>]" >&2; exit 2; } ;;
  --subiect)  [ $# -eq 2 ] || { echo "utilizare: sh $0 --subiect <subiect>" >&2; exit 2; }; MOD=subiect; CE=$2 ;;
  -*)         echo "utilizare: sh $0 [<id> | --subiect <subiect>]" >&2; exit 2 ;;
  *)          [ $# -eq 1 ] || { echo "utilizare: sh $0 [<id> | --subiect <subiect>]" >&2; exit 2; }; MOD=fisa; CE=$1 ;;
esac
for f in "$EV" "$EF" "$AF" "$SCRIPT_DIR/subiecte.tsv"; do
  [ -f "$f" ] || { echo "PROBLEMA lipseste $f" >&2; exit 1; }
done

W=$(mktemp -d /tmp/eveniment.XXXXXX) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

# subiectele si afirmatiile cunoscute
awk -F'\t' '!/^#/ && NF >= 2 { print $1 "\t" $2 }' "$SCRIPT_DIR/subiecte.tsv" > "$W/sub"
awk -F'\t' '!/^#/ && NF >= 2 { print $1 "\t" $NF }' "$AF" > "$W/af"

# 1. registrele: forma lor
awk -F'\t' -v fsub="$W/sub" -v faf="$W/af" -v fev="$EV" '
  function data(d) { return d ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
  FILENAME == fsub { S[$1] = 1; next }
  FILENAME == faf { A[$1] = 1; next }
  /^#/ || /^$/ { next }
  FILENAME == fev {
    if (NF != 7) { printf "PROBLEMA evenimente.tsv randul %d: %d coloane, trebuie 7\n", FNR, NF; rau = 1; next }
    if ($1 !~ /^[a-z0-9-]+$/) { printf "PROBLEMA evenimente.tsv randul %d: id „%s”\n", FNR, $1; rau = 1 }
    if ($1 in E) { printf "PROBLEMA evenimente.tsv randul %d: %s apare de doua ori\n", FNR, $1; rau = 1 }
    E[$1] = 1
    if (!data($2)) { printf "PROBLEMA evenimente.tsv randul %d: data „%s”\n", FNR, $2; rau = 1 }
    if ($6 != "-" && !data($6)) { printf "PROBLEMA evenimente.tsv randul %d: reverificare „%s”\n", FNR, $6; rau = 1 }
    if (!($3 in S)) { printf "PROBLEMA evenimente.tsv randul %d: subiect necunoscut „%s”\n", FNR, $3; rau = 1 }
    if ($4 != "-") { n = split($4, x, " "); for (i = 1; i <= n; i++) {
      if (!(x[i] in S)) { printf "PROBLEMA evenimente.tsv randul %d: subiect legat necunoscut „%s”\n", FNR, x[i]; rau = 1 }
      if (x[i] == $3) { printf "PROBLEMA evenimente.tsv randul %d: „%s” e si principal, si legat\n", FNR, x[i]; rau = 1 } } }
    n = split($5, x, " "); if (!n) { printf "PROBLEMA evenimente.tsv randul %d: nicio afirmatie\n", FNR; rau = 1 }
    for (i = 1; i <= n; i++) { EA[$1, x[i]] = 1
      if (!(x[i] in A)) { printf "PROBLEMA evenimente.tsv randul %d: afirmatie necunoscuta „%s”\n", FNR, x[i]; rau = 1 } }
    if ($7 == "") { printf "PROBLEMA evenimente.tsv randul %d: rezumat gol\n", FNR; rau = 1 }
    next }
  {
    if (NF != 7) { printf "PROBLEMA efecte.tsv randul %d: %d coloane, trebuie 7\n", FNR, NF; rau = 1; next }
    if (!($1 in E)) { printf "PROBLEMA efecte.tsv randul %d: eveniment necunoscut „%s”\n", FNR, $1; rau = 1 }
    if ($2 != "bine" && $2 != "rau" && $2 != "urmare") { printf "PROBLEMA efecte.tsv randul %d: fel „%s” (bine | rau | urmare)\n", FNR, $2; rau = 1 }
    if (!(($1, $3) in EA)) { printf "PROBLEMA efecte.tsv randul %d: afirmatia „%s” nu e trecuta la evenimentul %s\n", FNR, $3, $1; rau = 1 }
    if (($2 == "bine" || $2 == "rau") && ($4 == "-" || $4 == "")) { printf "PROBLEMA efecte.tsv randul %d: „%s” fara criteriu — fara criteriu numit e doar „urmare”\n", FNR, $2; rau = 1 }
    if ($2 == "urmare" && $4 != "-") { printf "PROBLEMA efecte.tsv randul %d: o urmare nu poarta criteriu („-”)\n", FNR; rau = 1 }
    if ($2 == "rau" && $5 != "documentata" && $5 != "nestabilita") { printf "PROBLEMA efecte.tsv randul %d: la rau, intentia e „documentata” sau „nestabilita”\n", FNR; rau = 1 }
    if ($2 != "rau" && $5 != "-") { printf "PROBLEMA efecte.tsv randul %d: intentia se scrie doar la rau\n", FNR; rau = 1 }
    if ($6 != "propus" && $6 != "aprobat") { printf "PROBLEMA efecte.tsv randul %d: stare „%s” (propus | aprobat)\n", FNR, $6; rau = 1 }
    if ($7 == "") { printf "PROBLEMA efecte.tsv randul %d: efect gol\n", FNR; rau = 1 }
  }
  END { exit rau }' "$W/sub" "$W/af" "$EV" "$EF" || exit 1

nume() { awk -F'\t' -v s="$1" '$1 == s { print $2; exit }' "$W/sub"; }

# fisa unui eveniment ($1 = id; $2 = „scurt” pentru lista unui subiect)
fisa() {
  awk -F'\t' -v id="$1" '!/^#/ && $1 == id { printf "\n%s  ·  %s\n  %s\n", $1, $2, $7 }' "$EV"
  sp=$(awk -F'\t' -v id="$1" '!/^#/ && $1 == id { print $3 }' "$EV")
  lg=$(awk -F'\t' -v id="$1" '!/^#/ && $1 == id { print $4 }' "$EV")
  rv=$(awk -F'\t' -v id="$1" '!/^#/ && $1 == id { print $6 }' "$EV")
  echo "  subiect: $sp — $(nume "$sp")"
  if [ "$lg" = "-" ]; then echo "  subiecte legate: niciunul"; else
    echo "  subiecte legate:"; for s in $lg; do echo "    $s — $(nume "$s")"; done; fi
  for fel in bine rau urmare; do
    case $fel in bine) t="In bine" ;; rau) t="In rau" ;; *) t="Urmari" ;; esac
    awk -F'\t' -v id="$1" -v fel="$fel" -v t="$t" '
      /^#/ || $1 != id || $2 != fel { next }
      !n++ { printf "\n  %s:\n", t }
      { printf "    - %s\n      afirmatia: %s", $7, $3
        if (fel != "urmare") printf "\n      criteriu: %s", $4
        if (fel == "rau") printf "\n      intentia: %s", $5
        printf "\n      numire: %s\n", ($6 == "aprobat" ? "aprobata de Bogdan" : "PROPUSA, neaprobata inca") }
      END { if (!n) printf "\n  %s: nimic inscris\n", t }' "$EF"
  done
  [ "${2:-}" = scurt ] && return
  echo ""
  echo "  De adus la zi cand se schimba ceva (termen: $rv):"
  for a in $(awk -F'\t' -v id="$1" '!/^#/ && $1 == id { print $5 }' "$EV"); do
    if [ -f "$TX" ] && grep -q "^$a	" "$TX"; then
      echo "    $a — text in texte.tsv: se schimba acolo, o data, apoi sh scripts/texte.sh --scrie"
      awk -F'\t' -v a="$a" '!/^#/ && $1 == a && $4 != "-" { n = split($4, f, " "); for (i = 1; i <= n; i++) printf "      %s (forma %s)\n", f[i], $2 }' "$TX"
    else
      echo "    $a — NEINSCRISA in texte.tsv: textul se schimba de mana, in fiecare pagina:"
      grep -l "data-afirmatie=\"$a\"" $(cat "$W/pagini") 2>/dev/null | sed "s|^$RADACINA/|      |"
    fi
  done
}

for R in $REPOURI; do
  [ -d "$RADACINA/$R" ] || continue
  find "$RADACINA/$R" -name .git -prune -o -type f -name '*.html' -print
done | sort > "$W/pagini"

case $MOD in
lista)
  echo ""
  echo "  eveniment                data        subiect            bine/rau/urmari  neaprobate  reverificare"
  awk -F'\t' -v fef="$EF" '
    FILENAME == fef { if ($0 !~ /^#/ && NF == 7) { c[$1, $2]++; if ($6 == "propus") p[$1]++ } next }
    /^#/ || NF != 7 { next }
    { printf "  %-24s %-11s %-18s %d/%d/%-12d %-11d %s\n", $1, $2, $3, c[$1, "bine"], c[$1, "rau"], c[$1, "urmare"], p[$1], $6 }' "$EF" "$EV" | sort -k2,2r
  echo ""
  echo "  $(grep -c '^[a-z0-9]' "$EV") evenimente.  Fisa: sh scripts/eveniment.sh <id>"
  ;;
fisa)
  grep -q "^$CE	" "$EV" || { echo "Niciun eveniment „$CE” in evenimente.tsv." >&2; exit 1; }
  fisa "$CE"; echo ""
  ;;
subiect)
  grep -q "^$CE	" "$W/sub" || { echo "Niciun subiect „$CE” in subiecte.tsv." >&2; exit 1; }
  echo ""
  echo "Evenimentele subiectului $CE — $(nume "$CE")"
  ai=$(awk -F'\t' -v s="$CE" '!/^#/ && NF == 7 && $3 == s { print $2 "\t" $1 }' "$EV" | sort -r | cut -f2)
  [ -n "$ai" ] || echo "  niciunul inscris"
  for e in $ai; do fisa "$e" scurt; done
  echo ""
  echo "Ajung la $CE dinspre alte subiecte:"
  al=$(awk -F'\t' -v s="$CE" '!/^#/ && NF == 7 && index(" " $4 " ", " " s " ") { print $2 "\t" $1 }' "$EV" | sort -r | cut -f2)
  [ -n "$al" ] || echo "  niciunul inscris"
  for e in $al; do fisa "$e" scurt; done
  echo ""
  ;;
esac
exit 0
