# lib.sh (pas183) - raportorii comuni ai regulilor din scripts/reguli/: o singura copie.
#
# Garda (verifica-site.sh, functia regula) citeste din iesirea fiecarei reguli randurile
# "  OK       ", "  PROBLEMA " si "  ATENTIE  " si le numara.  Forma lor e deci un contract:
# sta aici o data, nu copiata in fiecare regula.  Se incarca, dupa santinela, cu
#   [ -s "$SCRIPT_DIR/lib.sh" ] || { echo "lipseste scripts/lib.sh" >&2; exit 2; }
#   . "$SCRIPT_DIR/lib.sh"
# Garda si legaturi.sh au raportorii lor, care si numara (alt inteles): raman la ei.
# Sta in reguli.tsv cu amprenta lui (ca lib.awk) si sub sigiliu.  POSIX sh; numai ASCII.
ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; }
atentie()  { echo "  ATENTIE  $1"; }
