#!/bin/sh
# teste-garda.sh — suita de teste a verificarii (verifica-site.sh).  Din pas53.
#
# Fiecare test copiaza cele 6 clone intr-un director temporar, strica intentionat
# un singur lucru si ruleaza verificarea.  Verdictul asteptat e scris in test:
#   PICA   = verificarea trebuie sa blocheze (exit 1) si sa spuna de ce
#   TRECE  = verificarea trebuie sa treaca (exit 0)
#   DESCHIS = vulnerabilitate cunoscuta, inca nereparata (auditul din 19 oct);
#             se raporteaza, nu pica suita.  Cand e reparata, testul devine PICA.
# Clonele tale nu sunt atinse; nimic nu pleaca in retea (paginile GitHub, [12],
# sunt sarite prin NORGEDAN_API_DIR inexistent).
#
# Utilizare:
#   sh ~/norgedan.github.io/scripts/teste-garda.sh              toate testele
#   sh ~/norgedan.github.io/scripts/teste-garda.sh T03 T05      doar acestea
#   SCRIPT=/cale/alt-verifica-site.sh sh ...teste-garda.sh      contra-proba:
#        aceleasi teste pe alta versiune a verificarii (de ex. cea veche,
#        care trebuie sa pice testele noi)
# Cod de iesire: 0 = toate verdictele asteptate, 1 = cel putin unul gresit.
# Portabil POSIX — BSD si GNU: fara sed -i, fara \n in sed, fara bash.

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
HUB=$(dirname "$SCRIPT_DIR")
RADACINA=$(dirname "$HUB")
VERIF="${SCRIPT:-$SCRIPT_DIR/verifica-site.sh}"
[ -f "$VERIF" ] || { echo "nu gasesc $VERIF" >&2; exit 2; }
REPOS="norgedan.github.io corpus corpus2 opera limba limba-ro-final"
NO1930="$RADACINA/biblii/Norsk-1930.json"
[ -f "$NO1930" ] || { echo "teste-garda: lipseste $NO1930 (testele [14] au nevoie de el)" >&2; exit 2; }

T=$(mktemp -d /tmp/teste-garda.XXXXXX) || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 1' INT TERM

gresite=0; deschise=0; rulate=0
ALES="$*"

# rep <fisier> <expresie sed> — inlocuire pe loc, portabil (fara sed -i)
rep() { sed -e "$2" "$1" > "$1.t" && mv "$1.t" "$1"; }
# toate fisierele-document (din manifest), cale relativa la radacina copiei
docs() { grep -v '^#' "$C/norgedan.github.io/scripts/documente.tsv" | grep -v '^[[:space:]]*$' | awk -F'\t' '{print $3 "/" $4; print $3 "/" $5}'; }
docs_no() { grep -v '^#' "$C/norgedan.github.io/scripts/documente.tsv" | grep -v '^[[:space:]]*$' | awk -F'\t' '{print $3 "/" $5}'; }

# pregatire: copie curata, cu verificarea de testat pusa in hub
pregateste() {
  C="$T/r"; rm -rf "$C"; mkdir -p "$C/biblii"
  for r in $REPOS; do cp -R "$RADACINA/$r" "$C/$r" || return 1; done
  cp "$NO1930" "$C/biblii/Norsk-1930.json"
  cp "$VERIF" "$C/norgedan.github.io/scripts/verifica-site.sh"
}

# t <id> <PICA|TRECE|DESCHIS> <tipar asteptat in iesire> <descriere>
# mutatia se face in functia mut_<id>, in directorul copiei
t() {
  id=$1; astept=$2; tip=$3; descr=$4
  if [ -n "$ALES" ] && ! echo " $ALES " | grep -qF " $id "; then return; fi
  pregateste || { echo "$id  NU POT COPIA CLONELE"; gresite=$((gresite + 1)); return; }
  ( cd "$C" && "mut_$id" ) || { echo "$id  MUTATIA A ESUAT — testul nu mai corespunde site-ului"; gresite=$((gresite + 1)); return; }
  ( cd "$C" && NORGEDAN_API_DIR=/nu-exista sh norgedan.github.io/scripts/verifica-site.sh --ci ) > "$T/out" 2>&1
  ex=$?; rulate=$((rulate + 1))
  grep -qF -- "$tip" "$T/out" && semnalat=1 || semnalat=0
  case "$astept" in
    PICA)    [ "$ex" -eq 1 ] && [ "$semnalat" -eq 1 ] && v=bun || v=GRESIT ;;
    TRECE)   [ "$ex" -eq 0 ] && v=bun || v=GRESIT ;;
    DESCHIS) if [ "$ex" -eq 1 ] && [ "$semnalat" -eq 1 ]; then v="REPARAT? — fa-l PICA"; else v=deschis; fi ;;
  esac
  case "$v" in
    bun)     printf '  ok       %-4s %-7s %s\n' "$id" "$astept" "$descr" ;;
    deschis) printf '  deschis  %-4s %-7s %s\n' "$id" "$astept" "$descr"; deschise=$((deschise + 1)) ;;
    *)       printf '  GRESIT   %-4s %-7s %s  (exit %s, semnalat %s)\n' "$id" "$astept" "$descr" "$ex" "$semnalat"
             grep -e PROBLEMA -e REZULTAT "$T/out" | head -5 | sed 's/^/             /'
             gresite=$((gresite + 1)) ;;
  esac
}

# ── martorul: copia neatinsa trebuie sa treaca ─────────────────────────────
mut_T00() { :; }

# ── pas53: lipsa de date nu mai trece in tacere ────────────────────────────
mut_T01() { rm biblii/Norsk-1930.json; }
mut_T02() { echo x >> biblii/Norsk-1930.json; }
# toate blocurile de citat cu alta clasa: zero citate confruntate
mut_T03() { docs | while read -r f; do rep "$f" 's/<blockquote class="verse">/<blockquote class="verse x">/g; s/<blockquote class="hero-verse">/<blockquote class="hero-verse x">/g'; done; }
# extragerea linkurilor stricata (in copia verificarii): zero trimiteri
mut_T04() { rep norgedan.github.io/scripts/verifica-site.sh 's/^\$1 == "a" || \$1 == "link" .*{$/$1 == "NIMIC" {/'; }
# un document fara niciun capitol citit
mut_T05() { f=$(docs_no | head -1); rep "$f" 's/<h2/<h4/g; s/<\/h2>/<\/h4>/g'; }

# ── garzile vechi, ca regresie: trebuie sa prinda in continuare ────────────
mut_T10() { f=$(docs_no | head -1); rep "$f" 's/<\/h1>/<\/h1><p>40.000 de neuroni în inimă<\/p>/'; }
mut_T11() { rep norgedan.github.io/index.html 's/over 181 000 ord/over 999 000 ord/'; }
mut_T12() { awk '/<\/urlset>/ {print "<url><loc>https://norgedan.github.io/corpus/fantoma.html</loc></url>"} {print}' corpus/sitemap.xml > x && mv x corpus/sitemap.xml; }
mut_T13() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/Forut for undergang går overmot/Forut for undergang går stolthet/'; }

# ── deschise: gasite in audit, de reparat in pas54-55 ──────────────────────
# exact blocul cu Ordspråkene 16:18: clasa schimbata si textul stricat
mut_T20() { f=corpus/06-mennesket-og-kunstig-intelligens-no.html
            awk '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) {
                     if (l[i] ~ /<blockquote class="verse">/ && l[i + 1] ~ /Forut for undergang/) sub(/class="verse"/, "class=\"verse x\"", l[i])
                     print l[i] } }' "$f" > "$f.t" && mv "$f.t" "$f"
            rep "$f" 's/Forut for undergang går overmot/Forut for undergang går stolthet/'; }
mut_T21() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/«Forut for undergang går overmot, og forut for fall stolt mot.»/«og»/'; }
mut_T22() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/i september 2023 kalte 124 forskere/i september 2023 kalte 999 forskere/'; }
mut_T23() { for f in corpus2/ro/A-firul-rosu-al-istoriei-ro.html corpus2/no/A-den-rode-traden-i-historien-no.html; do
              rep "$f" 's/<\/h1>/<\/h1><p><span data-afirmatie="iit-disputa">Forskningen a demonstrat totul.<\/span><\/p>/'; done; }
mut_T24() { f=$(docs_no | head -1); rep "$f" 's/<\/h1>/<\/h1><p>40.000 de neuroni în <em>inimă<\/em><\/p>/'; }
mut_T25() { rep norgedan.github.io/index.html 's/over 181 000 ord/over 999\&nbsp;000 ord/'; }
mut_T26() { tr -d '\n' < corpus/sitemap.xml | sed 's|</urlset>|<url><loc>https://norgedan.github.io/corpus/fantoma.html</loc></url><url><loc>https://norgedan.github.io/corpus/</loc></url></urlset>|' > x && mv x corpus/sitemap.xml; }

echo ""
echo "===================================================="
echo "  teste-garda.sh  ·  verificarea testata: $VERIF"
echo "===================================================="
t T00 TRECE   "Poti face push"          "martor: copia neatinsa trece"
t T01 PICA    "Norsk-1930.json"         "[14] textul NO lipseste"
t T02 PICA    "cksum"                   "[14] textul NO are alta amprenta"
t T03 PICA    "niciun citat"            "[14] zero citate confruntate (santinela)"
t T04 PICA    "nicio trimitere"         "[4] zero linkuri citite (santinela)"
t T05 PICA    "niciun capitol"          "[15] document fara <h2> citit (santinela)"
t T10 PICA    "40.000 de neuroni"       "[7] formulare retrasa"
t T11 PICA    "999 000"                 "[8] cifra declarata gresita"
t T12 PICA    "fantoma"                 "[6] adresa din sitemap fara pagina"
t T13 PICA    "Ordspråkene 16:18"       "[14] citat NO schimbat"
t T20 DESCHIS "Ordspråkene 16:18"       "[14] citat schimbat, ascuns de alta clasa (pas54)"
t T21 DESCHIS "Ordspråkene 16:18"       "[14] citat redus la un cuvant (pas54)"
t T22 DESCHIS "iit-disputa"             "[13] afirmatie verificata, text schimbat (pas54)"
t T23 DESCHIS "a demonstrat"            "[13] id refolosit ascunde o certitudine (pas54)"
t T24 DESCHIS "40.000 de neuroni"       "[7] formulare retrasa rupta de un tag (pas55)"
t T25 DESCHIS "999"                     "[8] cifra cu &nbsp; (pas55)"
t T26 DESCHIS "fantoma"                 "[6] sitemap pe un singur rand (pas55)"
echo ""
echo "  $rulate teste rulate · $gresite cu verdict gresit · $deschise vulnerabilitati inca deschise"
echo ""
[ "$gresite" -eq 0 ]
