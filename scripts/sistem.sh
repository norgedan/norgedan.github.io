#!/bin/sh
# sistem.sh (pas182) - harta sistemului norgedan, din scripts/sistem.tsv.  Doar CITESTE.
#
#   sh scripts/sistem.sh            fiecare script: rolul, ce citeste, ce scrie, cine il cheama
#   sh scripts/sistem.sh <registru> cine citeste si cine scrie un registru (ex: surse.tsv)
#   sh scripts/sistem.sh --help     acest text
#
# Manifestul e verificat de garda, regula [25]; aici doar se arata.
# POSIX sh si awk.
D=$(cd "$(dirname "$0")" && pwd) || exit 1
M="$D/sistem.tsv"
case "${1:-}" in
  --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
[ -s "$M" ] || { echo "sistem.sh: lipseste $M" >&2; exit 2; }
if [ -n "${1:-}" ]; then
  awk -F'\t' -v R="$1" '!/^#/ && NF == 6 {
      if (index("," $3 ",", "," R ",")) c = c "    " $1 "\n"
      if (index("," $4 ",", "," R ",")) s = s "    " $1 "\n" }
    END { printf "%s\n  citit de:\n%s  scris de:\n%s", R, (c == "" ? "    -\n" : c), (s == "" ? "    -\n" : s) }' "$M"
  exit 0
fi
awk -F'\t' '!/^#/ && NF == 6 {
    printf "%s  (%s)\n", $1, $2
    printf "    citeste:   %s\n", $3; printf "    scrie:     %s\n", $4
    printf "    chemat de: %s\n", $5; printf "    teste:     %s\n\n", $6; n++ }
  END { printf "%d scripturi.  Un registru: sh scripts/sistem.sh <nume>, ex. surse.tsv\n", n }' "$M"
