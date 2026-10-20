#!/bin/sh
# teste-garda.sh — suita de teste a verificarii (verifica-site.sh).  Din pas53.
#
# Fiecare test copiaza cele 6 clone intr-un director temporar, strica intentionat
# un singur lucru si ruleaza verificarea.  Verdictul asteptat e scris in test:
#   PICA   = verificarea trebuie sa blocheze (exit 1) si sa spuna de ce
#   TRECE  = verificarea trebuie sa treaca (exit 0)
#   DESCHIS = vulnerabilitate cunoscuta, inca nereparata (auditul din 19 oct);
#             se raporteaza, nu pica suita.  Cand e reparata, testul devine PICA.
#   SEMNAL = atentionarea asteptata trebuie sa apara (pentru regulile care doar semnaleaza)
#   TACE   = verificarea trece si tiparul NU apare (o acceptare care trebuie sa functioneze)
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
    SEMNAL)  [ "$semnalat" -eq 1 ] && v=bun || v=GRESIT ;;
    TACE)    [ "$ex" -eq 0 ] && [ "$semnalat" -eq 0 ] && v=bun || v=GRESIT ;;
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
# toate blocurile de citat cu o clasa fara cuvantul "verse": zero citate confruntate
# (din pas54, "verse x" e recunoscut corect ca citat — santinela se testeaza altfel)
mut_T03() { docs | while read -r f; do rep "$f" 's/<blockquote class="verse">/<blockquote class="citat">/g; s/<blockquote class="hero-verse">/<blockquote class="citat-erou">/g'; done; }
# extragerea linkurilor stricata (in copia verificarii): zero trimiteri
mut_T04() { rep norgedan.github.io/scripts/verifica-site.sh 's/^\$1 == "a" || \$1 == "link" .*{$/$1 == "NIMIC" {/'; }
# un document fara niciun capitol citit
mut_T05() { f=$(docs_no | head -1); rep "$f" 's/<h2/<h4/g; s/<\/h2>/<\/h4>/g'; }

# ── garzile vechi, ca regresie: trebuie sa prinda in continuare ────────────
mut_T10() { f=$(docs_no | head -1); rep "$f" 's/<\/h1>/<\/h1><p>40.000 de neuroni în inimă<\/p>/'; }
mut_T11() { rep norgedan.github.io/index.html 's/over 181 000 ord/over 999 000 ord/'; }
mut_T12() { awk '/<\/urlset>/ {print "<url><loc>https://norgedan.github.io/corpus/fantoma.html</loc></url>"} {print}' corpus/sitemap.xml > x && mv x corpus/sitemap.xml; }
mut_T13() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/Forut for undergang går overmot/Forut for undergang går stolthet/'; }

# ── pas54: [14] mai strict si amprentele afirmatiilor ──────────────────────
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
# trimitere biblica fara forma cap:vers
mut_T27() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/1 Mosebok 3:22/1 Mosebok 3.22/'; }
# bloc de citat fara nicio trimitere
mut_T28() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/^    Ordspråkene 16:18$//'; }
# o amprenta stearsa din amprente.tsv: marcajul ramane fara amprenta
mut_T29() { grep -v '^iit-disputa' norgedan.github.io/scripts/amprente.tsv > x && mv x norgedan.github.io/scripts/amprente.tsv; }
# fluxul corect: afirmatia schimbata, reverificata, apoi --amprente = trece
mut_T30() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's/i september 2023 kalte 124 forskere/i september 2023 kalte 124 forskere (124)/'
            NORGEDAN_API_DIR=/nu-exista sh norgedan.github.io/scripts/verifica-site.sh --amprente > /dev/null 2>&1; }
# o clasa care doar incepe cu "verse" nu e citat biblic: nu se confrunta
mut_T31() { f=corpus/06-mennesket-og-kunstig-intelligens-no.html
            awk '{ l[NR] = $0 } END { for (i = 1; i <= NR; i++) {
                     if (l[i] ~ /<blockquote class="verse">/ && l[i + 1] ~ /Forut for undergang/) sub(/class="verse"/, "class=\"versetul\"", l[i])
                     print l[i] } }' "$f" > "$f.t" && mv "$f.t" "$f"
            rep "$f" 's/Forut for undergang går overmot/Forut for undergang går stolthet/'; }

# ── pas55: textul normalizat, sitemap-ul, [9] mai larg, acceptarile pe fisier ──
mut_T24() { f=$(docs_no | head -1); rep "$f" 's/<\/h1>/<\/h1><p>40.000 de neuroni în <em>inimă<\/em><\/p>/'; }
mut_T25() { rep norgedan.github.io/index.html 's/over 181 000 ord/over 999\&nbsp;000 ord/'; }
# un <em> neinchis intr-un titlu (asa a stat un </em> ratacit in Firul Rosu A)
mut_T32() { rep corpus/06-mennesket-og-kunstig-intelligens-no.html 's|<h3>Kunnskapens tre — hvorfor det var forbudt</h3>|<h3>Kunnskapens tre — <em>hvorfor det var forbudt</h3>|'; }
# formulare retrasa cu &nbsp;
mut_T33() { f=$(docs_no | head -1); rep "$f" 's/<\/h1>/<\/h1><p>40.000\&nbsp;de neuroni în inimă<\/p>/'; }
# formulare retrasa rupta pe doua randuri
mut_T34() { f=$(docs_no | head -1)
            awk '{ print } /<\/h1>/ && !g { print "<p>40.000 de neuroni"; print "în inimă</p>"; g = 1 }' "$f" > "$f.t" && mv "$f.t" "$f"; }
# o certitudine noua; fragmentul acceptat e legat de ALT fisier: nu are voie s-o ascunda
mut_T35() { rep corpus2/ro/A-firul-rosu-al-istoriei-ro.html 's/<\/h1>/<\/h1><p>Cercetarea a demonstrat totul aici.<\/p>/'
            printf 'corpus/01-la-inceput-era-cuvantul-ro.html\tCercetarea a demonstrat totul aici.\n' >> norgedan.github.io/scripts/certitudini-ok.txt; }
# acelasi fragment, legat de fisierul lui: acceptat
mut_T36() { rep corpus2/ro/A-firul-rosu-al-istoriei-ro.html 's/<\/h1>/<\/h1><p>Cercetarea a demonstrat totul aici.<\/p>/'
            printf 'corpus2/ro/A-firul-rosu-al-istoriei-ro.html\tCercetarea a demonstrat totul aici.\n' >> norgedan.github.io/scripts/certitudini-ok.txt; }
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
t T20 PICA    "Ordspråkene 16:18"       "[14] citat schimbat, ascuns de alta clasa"
t T21 PICA    "citat prea scurt"        "[14] citat redus la un cuvant"
t T22 PICA    "iit-disputa"             "[13] afirmatie verificata, text schimbat"
t T23 PICA    "marcaj fara amprenta"    "[13] id refolosit in alt document"
t T27 PICA    "fara forma carte"        "[14] trimitere biblica stricata (3.22)"
t T28 PICA    "fara trimitere"          "[14] bloc de citat fara trimitere"
t T29 PICA    "marcaj fara amprenta"    "[13] amprenta stearsa din amprente.tsv"
t T30 TRECE   "Poti face push"          "[13] text schimbat, reverificat, --amprente: trece"
t T31 TRECE   "Poti face push"          "[14] clasa \"versetul\" nu e citat: ignorata"
t T24 PICA    "40.000 de neuroni"       "[7] formulare retrasa rupta de un tag"
t T25 PICA    "999"                     "[8] cifra cu &nbsp;"
t T26 PICA    "fantoma"                 "[6] sitemap pe un singur rand"
t T32 PICA    "dezechilibrat"           "[9] <em> neinchis intr-un titlu"
t T33 PICA    "40.000 de neuroni"       "[7] formulare retrasa cu &nbsp;"
t T34 PICA    "40.000 de neuroni"       "[7] formulare retrasa pe doua randuri"
t T35 SEMNAL  "a demonstrat"            "[13] fragment acceptat pentru alt fisier nu ascunde"
t T36 TACE    "a demonstrat"            "[13] fragment acceptat pentru fisierul lui: tace"
echo ""
echo "  $rulate teste rulate · $gresite cu verdict gresit · $deschise vulnerabilitati inca deschise"
echo ""
[ "$gresite" -eq 0 ]
