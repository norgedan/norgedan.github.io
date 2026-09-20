#!/bin/sh
# verifica-hub.sh — control la nivel de site, nu de repo.  Versiunea 2.
#
# Ruleaza din radacina lui norgedan.github.io:  sh scripts/verifica-hub.sh
# Cod de iesire: 0 = curat, 1 = probleme gasite.
#   sh scripts/verifica-hub.sh && git push origin main
#
# De ce exista: scripts/verifica.sh din corpus verifica un repo in sine.
# Nu poate vedea ce se intampla INTRE repo-uri.  Pe 20 septembrie 2026,
# trei probleme au trait saptamani intregi in unghiul lui mort:
#   - Documentul VI, linkuit din corpus/index.html, dar nu si din hub
#   - cifra de cuvinte umflata in subsolul hub-ului
#   - o formulare retrasa dintr-un document, supravietuind pe prima pagina
# Fiecare dintre ele are aici o verificare dedicata.
#
# Paginile marcate cu noindex sunt documente interne, nu continut public:
# nu intra in numaratoare, nu se cere sa fie linkuite, si au voie sa citeze
# formulari retrase — ghidul si statusul exact asta fac.
#
# Portabil POSIX — BSD si GNU deopotriva.  Fara \n in sed, fara \| in grep,
# fara sed -i, fara conducte care pierd contorul.

BASE="https://norgedan.github.io"
REPOS="corpus corpus2 opera limba limba-ro-final"   # clone surori, langa acest repo
RADACINA=$(cd .. && pwd)                            # unde stau clonele

PROB=$(mktemp /tmp/verhub.XXXXXX) || exit 1
TMP=$(mktemp /tmp/verhub.XXXXXX)  || exit 1
TMP2=$(mktemp /tmp/verhub.XXXXXX) || exit 1
trap 'rm -f "$PROB" "$TMP" "$TMP2"' EXIT INT TERM
: > "$PROB"

ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; echo "x" >> "$PROB"; }
atentie()  { echo "  ATENTIE  $1"; }

echo ""
echo "===================================================="
echo "  Verificare la nivel de hub  ·  v2"
echo "  radacina clonelor: $RADACINA"
echo "===================================================="

# ─────────────────────────────────────────────────────
echo ""
echo "[1] Clonele surori exista"

DISPONIBILE=""
for r in $REPOS; do
  if [ -d "$RADACINA/$r" ]; then
    DISPONIBILE="$DISPONIBILE $r"
    ok "$r"
  else
    atentie "$r nu e clonat local — verificarile care il privesc se sar"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[2] Fiecare repo e linkuit din index.html"

for r in $DISPONIBILE; do
  if grep -q "$BASE/$r/" index.html; then
    ok "$r linkuit din hub"
  else
    problema "$r NU e linkuit din index.html — invizibil din pagina de start"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[3] Linkuire partiala — semnul documentului uitat"
# Daca hub-ul linkuieste unele documente ale unui repo, dar nu pe toate,
# inseamna ca s-a adaugat un document si hub-ul a ramas in urma.
# Zero linkuri e in regula: repo-ul e prezentat doar prin folderul lui.

for r in $DISPONIBILE; do
  : > "$TMP"
  for f in "$RADACINA/$r"/*.html "$RADACINA/$r"/ro/*.html "$RADACINA/$r"/no/*.html; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "index.html" ] && continue
    grep -q 'name="robots"[^>]*noindex' "$f" && continue
    echo "$b" >> "$TMP"
  done
  total=$(wc -l < "$TMP" | tr -d ' ')
  [ "$total" -eq 0 ] && continue

  linkuite=0
  while read -r b; do
    [ -z "$b" ] && continue
    grep -q "$b" index.html && linkuite=$((linkuite + 1))
  done < "$TMP"

  if [ "$linkuite" -eq 0 ]; then
    ok "$r — prezentat prin folder ($total documente, niciunul linkuit direct)"
  elif [ "$linkuite" -eq "$total" ]; then
    ok "$r — toate cele $total documente linkuite din hub"
  else
    problema "$r — hub-ul linkuieste $linkuite din $total documente; lipsesc:"
    while read -r b; do
      [ -z "$b" ] && continue
      grep -q "$b" index.html || echo "             $b"
    done < "$TMP"
  fi
done

# ─────────────────────────────────────────────────────
echo ""
echo "[4] Indexul de sitemap-uri trimite spre fisiere reale"

if [ -f sitemap.xml ]; then
  grep -o "$BASE/[^<]*" sitemap.xml | sed "s|$BASE/||" | sort -u > "$TMP"
  while read -r u; do
    [ -z "$u" ] && continue
    prim=$(echo "$u" | sed 's|/.*||')
    rest=$(echo "$u" | sed 's|^[^/]*/||')
    tinta="./$u"
    for r in $REPOS; do
      [ "$prim" = "$r" ] && tinta="$RADACINA/$r/$rest"
    done
    if [ -f "$tinta" ]; then
      n=$(grep -c '<loc>' "$tinta" 2>/dev/null | tr -d ' ')
      if [ "$n" -gt 0 ]; then
        ok "$u ($n URL-uri)"
      else
        problema "$u exista dar nu contine niciun <loc> — sitemap gol"
      fi
    else
      problema "$u e in indexul de sitemap-uri, dar nu exista la $tinta"
    fi
  done < "$TMP"
else
  problema "sitemap.xml nu exista"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[5] Fiecare document e in sitemap-ul repo-ului sau"

for r in $DISPONIBILE; do
  sm="$RADACINA/$r/sitemap.xml"
  if [ ! -f "$sm" ]; then
    atentie "$r nu are sitemap.xml propriu"
    continue
  fi
  lipsa=0
  for f in "$RADACINA/$r"/*.html "$RADACINA/$r"/ro/*.html "$RADACINA/$r"/no/*.html; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "index.html" ] && continue
    grep -q 'name="robots"[^>]*noindex' "$f" && continue
    if ! grep -q "$b" "$sm"; then
      problema "$r/$b nu e in $r/sitemap.xml"
      lipsa=1
    fi
  done
  [ "$lipsa" = "0" ] && ok "$r — toate documentele sunt in sitemap"
done

# la fel pentru documentele din acest repo (corpus3 si radacina)
if [ -f sitemap-hub.xml ]; then
  lipsa=0
  for f in ./*.html ./corpus3/ro/*.html ./corpus3/no/*.html; do
    [ -f "$f" ] || continue
    grep -q 'name="robots"[^>]*noindex' "$f" && continue
    case "$f" in ./google*.html|./404.html) continue ;; esac
    b=$(echo "$f" | sed 's|^\./||')
    if [ "$b" = "index.html" ]; then continue; fi
    if ! grep -q "$b" sitemap-hub.xml; then
      problema "$b nu e in sitemap-hub.xml"
      lipsa=1
    fi
  done
  [ "$lipsa" = "0" ] && ok "hub + corpus3 — toate documentele sunt in sitemap-hub.xml"
else
  atentie "sitemap-hub.xml nu exista"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[6] Paginile cu noindex NU sunt in niciun sitemap"
# Un fisier pe care il ceri neindexat nu are ce cauta intr-un sitemap:
# ii spui lui Google doua lucruri contrare in acelasi timp.

gasit_noindex=0
for f in ./*.html; do
  [ -f "$f" ] || continue
  grep -q 'name="robots"[^>]*noindex' "$f" || continue
  b=$(echo "$f" | sed 's|^\./||')
  for sm in sitemap.xml sitemap-hub.xml; do
    [ -f "$sm" ] || continue
    if grep -q "$b" "$sm"; then
      problema "$b are noindex dar apare in $sm"
      gasit_noindex=1
    fi
  done
done
[ "$gasit_noindex" = "0" ] && ok "niciun conflict noindex/sitemap"

# ─────────────────────────────────────────────────────
echo ""
echo "[7] Formulari retrase — supravietuiesc in alta parte?"
# Cand o afirmatie e corectata intr-un document, ea ramane adesea vie
# in indexuri, rezumate sau carduri.  Tiparele se tin in scripts/retrase.txt:
#   un tipar pe linie, comentariile incep cu #

RETRASE="scripts/retrase.txt"
if [ -f "$RETRASE" ]; then
  gasit_retras=0
  grep -v '^#' "$RETRASE" | grep -v '^[[:space:]]*$' > "$TMP"
  while read -r tipar; do
    [ -z "$tipar" ] && continue
    : > "$TMP2"
    for d in . $(for r in $DISPONIBILE; do echo "$RADACINA/$r"; done); do
      find "$d" \( -name '*.html' -o -name '*.md' \) -type f 2>/dev/null > "$TMP2.f"
      while read -r cand; do
        [ -z "$cand" ] && continue
        # paginile interne (noindex) au voie sa citeze ce s-a retras
        grep -q 'name="robots"[^>]*noindex' "$cand" && continue
        grep -qF "$tipar" "$cand" && echo "$cand" >> "$TMP2"
      done < "$TMP2.f"
      rm -f "$TMP2.f"
    done
    n=$(sort -u "$TMP2" | wc -l | tr -d ' ')
    if [ "$n" -gt 0 ]; then
      problema "formularea retrasa \"$tipar\" apare in $n fisier(e):"
      sort -u "$TMP2" | sed 's|^|             |'
      gasit_retras=1
    fi
  done < "$TMP"
  [ "$gasit_retras" = "0" ] && ok "nicio formulare retrasa nu a supravietuit"
else
  atentie "$RETRASE nu exista — verificarea formularilor retrase nu ruleaza"
fi

# ─────────────────────────────────────────────────────
echo ""
echo "[8] Cifra de cuvinte declarata in index.html vs. realitate"

LOCALE_NUM=""
for L in C.UTF-8 en_US.UTF-8 ro_RO.UTF-8; do
  if echo "a" | LC_ALL="$L" wc -w >/dev/null 2>&1; then
    LOCALE_NUM="$L"; break
  fi
done
[ -z "$LOCALE_NUM" ] && LOCALE_NUM="C"

: > "$TMP"
for r in $DISPONIBILE; do
  for f in "$RADACINA/$r"/*.html "$RADACINA/$r"/ro/*.html "$RADACINA/$r"/no/*.html; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "index.html" ] && continue
    grep -q 'name="robots"[^>]*noindex' "$f" && continue
    echo "$f" >> "$TMP"
  done
done
for f in ./corpus3/ro/*.html ./corpus3/no/*.html; do
  [ -f "$f" ] || continue
  [ "$(basename "$f")" = "index.html" ] && continue
  echo "$f" >> "$TMP"
done

real=0
docs=0
while read -r f; do
  [ -z "$f" ] && continue
  docs=$((docs + 1))
  n=$(awk '/<style>/{s=1} /<\/style>/{s=0;next} !s' "$f" \
      | sed 's/<[^>]*>//g' | LC_ALL="$LOCALE_NUM" wc -w | tr -d ' ')
  real=$((real + n))
done < "$TMP"

echo "  Masurat: $real cuvinte in $docs fisiere   [locale: $LOCALE_NUM]"

declarat=$(grep -oE '[0-9][0-9.]{4,}( de)? cuvinte' index.html | head -1)
if [ -z "$declarat" ]; then
  atentie "index.html nu declara un numar de cuvinte"
else
  cifre=$(echo "$declarat" | tr -cd '0-9')
  jos=$((real * 90 / 100))
  sus=$((real * 110 / 100))
  if [ "$cifre" -ge "$jos" ] && [ "$cifre" -le "$sus" ]; then
    ok "index.html declara \"$declarat\" — corespunde"
  else
    problema "index.html declara \"$declarat\", dar masuratoarea da $real"
  fi
fi

# ─────────────────────────────────────────────────────
probleme=$(wc -l < "$PROB" | tr -d ' ')

echo ""
echo "===================================================="
if [ "$probleme" -eq 0 ]; then
  echo "  REZULTAT: totul in regula. Poti face push."
  echo "===================================================="
  echo ""
  exit 0
else
  echo "  REZULTAT: $probleme probleme gasite. NU face push."
  echo "===================================================="
  echo ""
  exit 1
fi
