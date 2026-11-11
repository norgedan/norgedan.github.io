#!/bin/sh
# 24-sigiliu.sh — regula [24] a garzii norgedan (pas141): sigiliul lui Bogdan, intrebat si de garda.
#
# Paznicul (scripts/pazitor.sh, instalat in <radacina>/.norgedan/) opreste la push o garda
# schimbata fara sigiliu nou.  Regula aceasta pune aceeasi intrebare la FIECARE rulare a
# garzii, nu doar la push: asa se vede din timp ca scripturile s-au schimbat si cer sigilare.
# Ea nu e ancora de siguranta (o garda schimbata ar putea-o sari) — ancora e paznicul, care
# ruleaza inaintea garzii.  Aici doar aratam starea, cinstit:
#   - paznic neinstalat pe acest calculator (CI, copiile suitei): se spune, fara semnal;
#   - nesigilat sau scripturi schimbate de la sigilare: ATENTIE, cu lista si comanda;
#   - paznicul instalat difera de cel din hub: ATENTIE (hub-ul s-a schimbat; cel instalat
#     ramane cel citit de om, pana il reinstaleaza el).
#
# Chemare:  sh 24-sigiliu.sh <scripts> <pregatire>
SCRIPT_DIR=$1; W=$2
[ -d "$SCRIPT_DIR" ] && [ -d "$W" ] || { echo "utilizare: sh $0 <scripts> <pregatire>" >&2; exit 2; }
ok()      { echo "  OK       $1"; }
atentie() { echo "  ATENTIE  $1"; }
problema() { echo "  PROBLEMA $1"; }
N="$(dirname "$(dirname "$SCRIPT_DIR")")/.norgedan"

# pas143: paznicul e singurul script pe care omul il citeste intreg, in terminal (less),
# inainte sa-l instaleze; acolo o liniuta lunga apare ca <E2><80><94>.  Deci doar ASCII.
# Se verifica si unde paznicul nu e instalat (CI, copiile suitei).
if [ -f "$SCRIPT_DIR/pazitor.sh" ] && LC_ALL=C grep -q '[^ -~	]' "$SCRIPT_DIR/pazitor.sh"; then
  problema "scripts/pazitor.sh are caractere care nu sunt ASCII — in terminal se citesc greu: $(LC_ALL=C grep -c '[^ -~	]' "$SCRIPT_DIR/pazitor.sh") randuri (LC_ALL=C grep -n '[^ -~]' scripts/pazitor.sh)"
fi

if [ ! -f "$N/pazitor.sh" ]; then
  ok "sigiliul: sarit — paznicul nu e instalat pe acest calculator ($N)"
  exit 0
fi
sh "$N/pazitor.sh" --verifica > "$W/r24.out" 2> "$W/r24.err"; c=$?
case $c in
  0) ok "sigiliul lui Bogdan: $(wc -l < "$N/sigiliu.tsv" | tr -d ' ') scripturi ale garzii, neschimbate de la sigilare" ;;
  1) atentie "scripturi ale garzii schimbate de la ultima sigilare — push-ul va fi oprit pana sigilezi (sh $N/pazitor.sh --sigileaza):"
     cat "$W/r24.out" ;;
  *) atentie "garda nu e sigilata sau paznicul n-a putut verifica (iesire $c): $(head -n 1 "$W/r24.out" "$W/r24.err" 2>/dev/null | grep -v '^==>' | grep -v '^$' | head -n 1) — sh $N/pazitor.sh --sigileaza" ;;
esac
cmp -s "$N/pazitor.sh" "$SCRIPT_DIR/pazitor.sh" || atentie "paznicul instalat difera de scripts/pazitor.sh din hub — citeste diferenta (diff $N/pazitor.sh $SCRIPT_DIR/pazitor.sh) si, daca o vrei, reinstaleaza: sh scripts/pazitor.sh --instaleaza"
exit 0
