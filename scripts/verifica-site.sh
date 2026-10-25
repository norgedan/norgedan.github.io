#!/bin/sh
# verifica-site.sh — verificarea unica a intregului site norgedan.  Versiunea 3.
#
# Inlocuieste scripts/verifica.sh (corpus) si scripts/verifica-hub.sh (hub).
# Sursa de adevar: scripts/documente.tsv — un rand = un document = o pereche RO+NO.
#
# Utilizare (din orice director):
#   sh ~/norgedan.github.io/scripts/verifica-site.sh            verificare completa
#   sh ~/norgedan.github.io/scripts/verifica-site.sh --tablou   doar tabloul
#   ... --github          ca mai sus + pagina GitHub a fiecarui repo (retea)
#   ... --ci              in GitHub Actions: tot, fara ce tine de clona locala
#   ... --push <repo>     folosit de hook-ul pre-push (aduce starea de pe GitHub)
#   ... --amprente        dupa ce o afirmatie a fost (re)verificata la sursa:
#                         rescrie scripts/amprente.tsv din paginile de acum
#   ... --capitole        dupa ce un capitol a fost (re)verificat la sursa (pas63):
#                         rescrie titlul si amprentele in scripts/capitole-verificate.tsv
#   ... --surse           ca verificarea manuala + citatele exacte din surse.tsv confruntate
#                         cu pagina lor, prin retea (pas68)
#
# Cod de iesire: 0 = curat, 1 = probleme, 2 = utilizare gresita.
#
# Portabil POSIX — BSD si GNU.  Fara \n in sed, fara \| in grep, fara sed -i,
# fara conducte care pierd contorul, fara intervale sed.
#
# Principii:
#  - HTML-ul se citeste ca tag-uri reale (awk, RS=">"), nu cu grep pe text:
#    un exemplu scris in <pre> nu mai poate pacali verificarea.
#  - Toate clonele sunt surori:  RADACINA/norgedan.github.io, RADACINA/corpus ...
#  - OK se afiseaza o data pe sectiune; problemele, fiecare in parte.

BASE="https://norgedan.github.io"

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 1
HUB=$(dirname "$SCRIPT_DIR")
HUBNAME=$(basename "$HUB")
RADACINA=$(dirname "$HUB")
MANIFEST="$SCRIPT_DIR/documente.tsv"
ABOUT="$SCRIPT_DIR/about.tsv"
RETRASE="$SCRIPT_DIR/retrase.txt"
AFIRMATII="$SCRIPT_DIR/afirmatii.tsv"
AMPRENTE="$SCRIPT_DIR/amprente.tsv"
CERT="$SCRIPT_DIR/certitudini.txt"
CERT_OK="$SCRIPT_DIR/certitudini-ok.txt"
TAB=$(printf '\t')

MOD=manual
PUSH_REPO=""
case "${1:-}" in
  "")        ;;
  --tablou)  MOD=tablou ;;
  --amprente) MOD=amprente ;;
  --capitole) MOD=capitole ;;
  --surse)   MOD=surse ;;
  --github)  MOD=github ;;
  --ci)      MOD=ci ;;
  --push)    MOD=push; PUSH_REPO="${2:-}" ;;
  *)         echo "utilizare: sh $0 [--tablou | --github | --ci | --push <repo> | --amprente | --capitole | --surse]" >&2; exit 2 ;;
esac

# Locale pentru numararea cuvintelor: wc -w numara diferit pe text cu
# diacritice in POSIX fata de UTF-8.  Primul locale UTF-8 disponibil.
LOCALE_NUM=C
for L in C.UTF-8 en_US.UTF-8 ro_RO.UTF-8; do
  if echo "a" | LC_ALL="$L" wc -w >/dev/null 2>&1; then LOCALE_NUM="$L"; break; fi
done

W=$(mktemp -d /tmp/verifica-site.XXXXXX) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 1' INT TERM
mkdir "$W/t"
: > "$W/prob"; : > "$W/aten"

# La push, git da hook-ului pe stdin ce pleaca:  ref-local sha-local ref-distant sha-distant.
# Se citeste aici, la inceput, inainte ca vreo comanda sa poata consuma stdin-ul (pas55).
: > "$W/pushin"
if [ "$MOD" = push ] && [ ! -t 0 ]; then cat > "$W/pushin"; fi

ok()       { echo "  OK       $1"; }
problema() { echo "  PROBLEMA $1"; echo x >> "$W/prob"; }
atentie()  { echo "  ATENTIE  $1"; echo x >> "$W/aten"; }
titlu()    { echo ""; echo "[$1] $2"; }

# ════════════════════════════════════════════════════════════════════
# Uneltele awk — scrise o data, folosite peste tot
# ════════════════════════════════════════════════════════════════════

# tags.awk: scoate tag-urile reale dintr-un fisier HTML.
# Iesire, cate o linie pe tag:   nume TAB atr TAB val TAB atr TAB val ...
# si pentru <title>:             TITLE TAB text
# Sare peste comentarii si peste continutul <style> / <script>.
cat > "$W/tags.awk" <<'AWK'
BEGIN { RS = ">"; incom = 0; raw = ""; intitle = 0 }
{
  r = $0
  gsub(/[\r\n\t]/, " ", r)
  if (incom) { if (r ~ /--$/) incom = 0; next }
  if (raw != "") {
    k = index(r, "</" raw)
    if (k > 0) raw = ""
    next
  }
  i = index(r, "<")
  if (i == 0) next
  text = substr(r, 1, i - 1)
  t = substr(r, i + 1)
  if (substr(t, 1, 3) == "!--") { if (t !~ /--$/) incom = 1; next }
  if (t ~ /^\//) {
    if (intitle && tolower(substr(t, 2, 5)) == "title") {
      sub(/^ +/, "", text); sub(/ +$/, "", text)
      print "TITLE\t" text
      intitle = 0
    }
    next
  }
  if (t !~ /^[a-zA-Z]/) next
  match(t, /^[a-zA-Z0-9]+/)
  name = tolower(substr(t, 1, RLENGTH))
  t = substr(t, RLENGTH + 1)
  line = name
  while (match(t, /[a-zA-Z_:][-a-zA-Z0-9_:.]* *= *"[^"]*"/)) {
    a = substr(t, RSTART, RLENGTH)
    t = substr(t, RSTART + RLENGTH)
    k = a; sub(/ *=.*/, "", k)
    v = a; sub(/^[^"]*"/, "", v); sub(/"$/, "", v)
    line = line "\t" tolower(k) "\t" v
  }
  print line
  if (name == "style" || name == "script") raw = name
  if (name == "title") intitle = 1
}
AWK

# attr.awk: dintr-un fisier de tag-uri, valorile atributului W ale
# tag-urilor T care au atributul K egal cu V  (K gol = orice tag T).
cat > "$W/attr.awk" <<'AWK'
BEGIN { FS = "\t" }
$1 == T {
  split("", a)
  for (i = 2; i < NF; i += 2) a[$i] = $(i + 1)
  if (K == "" || ((K in a) && a[K] == V)) if (Wn in a) print a[Wn]
}
AWK

# links.awk: toate trimiterile interne ale unei pagini, rezolvate.
# Intrare: fisierul de tag-uri.  Variabile: P (calea URL a paginii),
# BASE, RAD, HUB, REPOS (repo-urile, fara hub, separate prin spatiu).
# Iesire: fisier-tinta TAB ancora TAB href-original TAB cale-URL
cat > "$W/links.awk" <<'AWK'
function norm(p,   n, a, s, i, k, out) {
  n = split(p, a, "/"); k = 0; split("", s)
  for (i = 1; i <= n; i++) {
    if (a[i] == "" || a[i] == ".") continue
    if (a[i] == "..") { if (k > 0) k--; continue }
    s[++k] = a[i]
  }
  out = ""
  for (i = 1; i <= k; i++) out = out "/" s[i]
  if (out == "" || p ~ /\/$/ || a[n] == "." || a[n] == "..") out = out "/"
  return out
}
function tofile(p,   seg, rest, k, f) {
  seg = substr(p, 2); rest = ""
  k = index(seg, "/")
  if (k > 0) { rest = substr(seg, k + 1); seg = substr(seg, 1, k - 1) }
  if (seg in isrepo) f = RAD "/" seg "/" rest
  else f = HUB p
  if (f ~ /\/$/) f = f "index.html"
  return f
}
BEGIN {
  FS = "\t"
  n = split(REPOS, rr, " ")
  for (i = 1; i <= n; i++) isrepo[rr[i]] = 1
  dir = P; sub(/[^\/]*$/, "", dir)
}
$1 == "a" || $1 == "link" || $1 == "img" || $1 == "script" || $1 == "source" || $1 == "iframe" {
  for (i = 2; i < NF; i += 2) {
    if ($i != "href" && $i != "src") continue
    h = $(i + 1); orig = h
    frag = ""
    k = index(h, "#"); if (k > 0) { frag = substr(h, k + 1); h = substr(h, 1, k - 1) }
    k = index(h, "?"); if (k > 0) h = substr(h, 1, k - 1)
    if (index(h, BASE) == 1) { h = substr(h, length(BASE) + 1); if (h == "") h = "/" }
    else if (h ~ /^[a-zA-Z][a-zA-Z0-9+.-]*:/ || h ~ /^\/\//) continue
    if (h == "") p = P
    else if (h ~ /^\//) p = h
    else p = dir h
    p = norm(p)
    if (frag == "") frag = "-"      # camp gol: read cu IFS=TAB ar contopi tab-urile
    print tofile(p) "\t" frag "\t" orig "\t" p
  }
}
AWK

# fisier -> numele fisierului sau de tag-uri
tagsf() { echo "$W/t/$(echo "$1" | sed 's|/|_|g')"; }

# valoare de atribut:  val <fisier> <tag> <atr-cheie> <valoare-cheie> <atr-dorit>
val() { awk -v T="$2" -v K="$3" -v V="$4" -v Wn="$5" -f "$W/attr.awk" "$(tagsf "$1")"; }

# URL canonic pentru <repo> <cale>
url_of() {
  case "$2" in
    index.html)   p="" ;;
    */index.html) p="${2%index.html}" ;;
    *)            p="$2" ;;
  esac
  if [ "$1" = "$HUBNAME" ]; then echo "$BASE/$p"; else echo "$BASE/$1/$p"; fi
}

# cuvinte intr-un fisier: textul, fara CSS si fara cod JavaScript (<script>).
# Pana la 18 oct 2026 codul butonului „Asculta” se numara si el (275 de cuvinte).
cuvinte() {
  awk '/<style>/{s=1} /<\/style>/{s=0;next} /<script/{c=1} /<\/script>/{c=0;next} !s && !c' "$1" \
    | sed 's/<[^>]*>//g' | LC_ALL="$LOCALE_NUM" wc -w | tr -d ' '
}

# textul unei pagini pentru cautari (pas55): fara CSS si cod, fara tag-uri, cu
# &nbsp; si spatiul neseparabil (U+00A0) ca spatiu, totul pe un rand, spatiile unificate.
# O formulare sau o cifra rupta de un tag (<em>), de &nbsp; sau de un rand nou
# nu mai scapa nevazuta.  Octet cu octet (LC_ALL=C), identic pe BSD si GNU.
NBSP=$(printf '\302\240')
text_normalizat() {
  awk '/<style>/{s=1} /<\/style>/{s=0;next} /<script/{c=1} /<\/script>/{c=0;next} !s && !c' "$1" \
    | tr '\n\r\t' '   ' | LC_ALL=C sed -e 's/<[^>]*>/ /g' -e 's/&nbsp;/ /g' -e "s/$NBSP/ /g" | tr -s ' '
}

# pagina interna = marcata noindex
e_intern() {
  awk -v T=meta -v K=name -v V=robots -v Wn=content -f "$W/attr.awk" "$(tagsf "$1")" \
    | grep -q noindex
}

echo ""
echo "===================================================="
echo "  verifica-site.sh  ·  v3  ·  mod: $MOD"
echo "  radacina clonelor: $RADACINA"
echo "===================================================="

# ════════════════════════════════════════════════════════════════════
titlu 1 "Manifestul documente.tsv"
# ════════════════════════════════════════════════════════════════════

if [ ! -f "$MANIFEST" ]; then
  problema "lipseste $MANIFEST — fara manifest nu exista tablou"
  echo ""; echo "  REZULTAT: manifest absent. NU face push."; exit 1
fi

grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' > "$W/m"

awk -F'\t' '
  NF != 7 { print "rand " NR ": " NF " coloane, trebuie 7"; next }
  {
    for (i = 1; i <= 7; i++) if ($i == "") print "rand " NR ": coloana " i " e goala"
    if (id[$1]++)            print "id duplicat: " $1
    if (f[$3 "/" $4]++)      print "fisier folosit de doua ori: " $3 "/" $4
    if (f[$3 "/" $5]++)      print "fisier folosit de doua ori: " $3 "/" $5
  }' "$W/m" > "$W/merr"

if [ -s "$W/merr" ]; then
  while read -r l; do problema "manifest: $l"; done < "$W/merr"
else
  ok "$(wc -l < "$W/m" | tr -d ' ') documente, structura corecta"
fi

# repo-urile, in ordinea din manifest; hub-ul e mereu inclus
{ echo "$HUBNAME"; cut -f3 "$W/m"; } | awk '!s[$0]++' > "$W/repos"
REPOS_FARA_HUB=$(grep -vx "$HUBNAME" "$W/repos" | tr '\n' ' ')

# lista plata a fisierelor-document:  repo TAB cale TAB limba TAB id TAB colectie TAB titlu
awk -F'\t' 'BEGIN{OFS="\t"} {print $3,$4,"ro",$1,$2,$6; print $3,$5,"no",$1,$2,$7}' "$W/m" > "$W/docs"

# ════════════════════════════════════════════════════════════════════
# Tabloul (si modul --tablou)
# ════════════════════════════════════════════════════════════════════

: > "$W/cuv"
while IFS="$TAB" read -r repo cale limba id col tit; do
  f="$RADACINA/$repo/$cale"
  n=0; [ -f "$f" ] && n=$(cuvinte "$f")
  printf '%s\t%s\t%s\t%s\n' "$col" "$limba" "$n" "$id" >> "$W/cuv"
done < "$W/docs"

tablou() {
  echo ""
  echo "  TABLOUL SITE-ULUI  (document = pereche RO+NO)"
  echo "  ----------------------------------------------------------------"
  awk -F'\t' '
    { if (!($1 in n)) ord[++k] = $1
      if ($2 == "ro") { n[$1]++; ro[$1] += $3 } else no[$1] += $3 }
    END {
      printf "  %-16s %10s %10s %10s %10s\n", "colectie", "documente", "cuv. RO", "cuv. NO", "total"
      for (i = 1; i <= k; i++) {
        c = ord[i]; t = ro[c] + no[c]
        printf "  %-16s %10d %10d %10d %10d\n", c, n[c], ro[c], no[c], t
        N += n[c]; R += ro[c]; O += no[c]
      }
      printf "  %-16s %10d %10d %10d %10d\n", "TOTAL", N, R, O, R + O
    }' "$W/cuv"
  echo "  ----------------------------------------------------------------"
  echo "  numarat fara CSS, cod si tag-uri, locale $LOCALE_NUM"
  if [ -f "$AFIRMATII" ]; then
    grep -v '^#' "$AFIRMATII" | grep -v '^[[:space:]]*$' | awk -F'\t' '
      { n++; s[$3]++ }
      END { printf "  afirmatii in registru: %d  (verificate %d, de verificat %d, de corectat %d)\n", n, s["verificat"], s["de-verificat"], s["de-corectat"] }'
  fi
}

TOTAL_CUV=$(awk -F'\t' '{s += $3} END {print s + 0}' "$W/cuv")

if [ "$MOD" = "tablou" ]; then tablou; echo ""; exit 0; fi

# ════════════════════════════════════════════════════════════════════
titlu 2 "Inventar: fiecare pagina de pe disc e cunoscuta"
# ════════════════════════════════════════════════════════════════════
# Orice .html e fie document din manifest, fie pagina de structura
# (index.html, 404.html, verificarea Google), fie pagina interna (noindex).
# Altceva = fisier pe care tabloul nu-l cunoaste.

: > "$W/html"
while read -r repo; do
  d="$RADACINA/$repo"
  if [ ! -d "$d" ]; then problema "clona $repo lipseste din $RADACINA"; continue; fi
  find "$d" -name .git -prune -o -type f -name '*.html' -print | sort >> "$W/html"
done < "$W/repos"

while read -r f; do awk -f "$W/tags.awk" "$f" > "$(tagsf "$f")"; done < "$W/html"

necunoscute=0
while read -r f; do
  rel=${f#"$RADACINA"/}
  repo=${rel%%/*}; cale=${rel#*/}
  if awk -F'\t' -v r="$repo" -v c="$cale" '$1==r && $2==c {g=1} END {exit !g}' "$W/docs"; then continue; fi
  case "$cale" in index.html|*/index.html|404.html|google*.html) continue ;; esac
  e_intern "$f" && continue
  problema "$rel nu e in manifest (nici structura, nici noindex)"
  necunoscute=$((necunoscute + 1))
done < "$W/html"

lipsa=0
while IFS="$TAB" read -r repo cale limba id col tit; do
  if [ ! -f "$RADACINA/$repo/$cale" ]; then
    problema "$id ($limba): $repo/$cale e in manifest dar nu exista pe disc"
    lipsa=$((lipsa + 1))
  fi
done < "$W/docs"
# santinela: nicio pagina gasita = cautarea s-a stricat, nu un site curat
[ -s "$W/html" ] || { problema "nicio pagina .html gasita sub $RADACINA — cautarea s-a stricat"; necunoscute=1; }
[ "$necunoscute" -eq 0 ] && [ "$lipsa" -eq 0 ] && \
  ok "$(wc -l < "$W/html" | tr -d ' ') pagini pe disc, toate cunoscute; $(wc -l < "$W/docs" | tr -d ' ') fisiere-document prezente"

# ════════════════════════════════════════════════════════════════════
titlu 3 "Fiecare document: titlu, lang, meta, canonical, hreflang, og"
# ════════════════════════════════════════════════════════════════════

: > "$W/descr"
greseli=0
while IFS="$TAB" read -r repo cale limba id col tit; do
  f="$RADACINA/$repo/$cale"
  [ -f "$f" ] || continue
  eu=$(url_of "$repo" "$cale")
  ro_c=$(awk -F'\t' -v i="$id" '$1==i {print $3 "\t" $4}' "$W/m")
  ro_url=$(url_of "${ro_c%%"$TAB"*}" "${ro_c#*"$TAB"}")
  no_c=$(awk -F'\t' -v i="$id" '$1==i {print $3 "\t" $5}' "$W/m")
  no_url=$(url_of "${no_c%%"$TAB"*}" "${no_c#*"$TAB"}")
  [ "$limba" = ro ] && lang_ok=ro || lang_ok=nb
  e="$id ($limba) $repo/$cale"
  before=$(wc -l < "$W/prob")

  t=$(awk -F'\t' '$1=="TITLE" {print $2; exit}' "$(tagsf "$f")")
  [ "$t" = "$tit" ] || problema "$e: <title> difera de manifest"

  l=$(val "$f" html "" "" lang | head -1)
  [ "$l" = "$lang_ok" ] || problema "$e: lang=\"$l\", trebuie \"$lang_ok\""

  e_intern "$f" && problema "$e: document public marcat noindex"

  nd=$(val "$f" meta name description content | wc -l | tr -d ' ')
  if [ "$nd" -ne 1 ]; then
    problema "$e: $nd meta description (trebuie exact 1)"
  else
    printf '%s\t%s\n' "$(val "$f" meta name description content)" "$e" >> "$W/descr"
  fi

  c=$(val "$f" link rel canonical href)
  [ "$c" = "$eu" ] || problema "$e: canonical \"${c:-lipsa}\", trebuie $eu"

  for pereche in "ro $ro_url" "nb $no_url" "x-default $ro_url"; do
    hl=${pereche%% *}; asteptat=${pereche#* }
    h=$(val "$f" link hreflang "$hl" href)
    [ "$h" = "$asteptat" ] || problema "$e: hreflang=\"$hl\" -> \"${h:-lipsa}\", trebuie $asteptat"
  done
  [ -n "$(val "$f" link hreflang no href)" ] && problema "$e: foloseste hreflang=\"no\" — standardul site-ului e \"nb\""

  for p in og:title og:description; do
    [ -n "$(val "$f" meta property "$p" content)" ] || problema "$e: lipseste $p"
  done
  ou=$(val "$f" meta property og:url content)
  [ "$ou" = "$eu" ] || problema "$e: og:url \"${ou:-lipsa}\", trebuie $eu"

  [ "$(wc -l < "$W/prob")" -gt "$before" ] && greseli=$((greseli + 1))
done < "$W/docs"
[ "$greseli" -eq 0 ] && ok "toate cele $(wc -l < "$W/docs" | tr -d ' ') fisiere-document sunt complete si coerente"

# descrieri identice intre documente diferite
cut -f1 "$W/descr" | sort | uniq -d > "$W/dup"
if [ -s "$W/dup" ]; then
  while read -r d; do problema "descriere identica in mai multe fisiere: $(echo "$d" | cut -c1-60)..."; done < "$W/dup"
else
  ok "nicio descriere duplicata"
fi
lungi=0
while IFS="$TAB" read -r d e; do
  n=$(printf '%s' "$d" | LC_ALL="$LOCALE_NUM" wc -m | tr -d ' ')
  [ "$n" -gt 160 ] && lungi=$((lungi + 1))
done < "$W/descr"
[ "$lungi" -gt 0 ] && atentie "$lungi descrieri au peste 160 de caractere (Google taie in jur de 155-160)"

# standardul "nb" peste tot, nu doar pe documente: si paginile de intrare
while read -r f; do
  rel=${f#"$RADACINA"/}; repo=${rel%%/*}; cale=${rel#*/}
  awk -F'\t' -v r="$repo" -v c="$cale" '$1==r && $2==c {g=1} END {exit !g}' "$W/docs" && continue
  e_intern "$f" && continue
  [ -n "$(val "$f" link hreflang no href)" ] && problema "$rel: foloseste hreflang=\"no\" — standardul site-ului e \"nb\""
done < "$W/html"

grep -q "${TAB}og:image$TAB" "$W"/t/* 2>/dev/null || atentie "nicio pagina nu are og:image — distribuirile apar fara imagine"

# ════════════════════════════════════════════════════════════════════
titlu 4 "Linkuri interne si ancore — tot site-ul, din tag-uri reale"
# ════════════════════════════════════════════════════════════════════

: > "$W/links"
while read -r f; do
  rel=${f#"$RADACINA"/}
  repo=${rel%%/*}; cale=${rel#*/}
  if [ "$repo" = "$HUBNAME" ]; then P="/$cale"; else P="/$repo/$cale"; fi
  awk -v P="$P" -v BASE="$BASE" -v RAD="$RADACINA" -v HUB="$HUB" -v REPOS="$REPOS_FARA_HUB" \
      -f "$W/links.awk" "$(tagsf "$f")" | sed "s|^|$rel$TAB|" >> "$W/links"
done < "$W/html"

rupte=0
while IFS="$TAB" read -r sursa tinta frag orig cale; do
  [ -d "$tinta" ] && tinta="$tinta/index.html"
  if [ ! -f "$tinta" ]; then
    problema "$sursa -> $orig : pagina nu exista"
    rupte=$((rupte + 1)); continue
  fi
  if [ "$frag" != "-" ]; then
    tf=$(tagsf "$tinta")
    if [ -f "$tf" ] && ! awk -F'\t' -v x="$frag" '{for (i=2;i<NF;i+=2) if (($i=="id"||$i=="name") && $(i+1)==x) {g=1; exit}} END {exit !g}' "$tf"; then
      problema "$sursa -> $orig : ancora #$frag nu exista"
      rupte=$((rupte + 1))
    fi
  fi
done < "$W/links"
# santinela: zero trimiteri pe un site cu sute de linkuri = citirea s-a stricat
[ -s "$W/links" ] || { problema "nicio trimitere interna citita — extragerea linkurilor s-a stricat"; rupte=1; }
[ "$rupte" -eq 0 ] && ok "$(wc -l < "$W/links" | tr -d ' ') trimiteri interne, toate ajung la tinta"

# ════════════════════════════════════════════════════════════════════
titlu 5 "Hub-ul prezinta fiecare colectie"
# ════════════════════════════════════════════════════════════════════
# O colectie e prezentata fie document cu document (toate!), fie prin folder.
# Linkuirea partiala e semnul documentului uitat (asa a ramas Doc V NO).

awk -F'\t' -v h="$HUBNAME/index.html" '$1==h {print $5}' "$W/links" | sort -u > "$W/hubl"
greseli=0
for col in $(cut -f2 "$W/m" | awk '!s[$0]++'); do
  repo=$(awk -F'\t' -v c="$col" '$2==c {print $3; exit}' "$W/m")
  if [ "$repo" = "$HUBNAME" ]; then folder="/$col/"; else folder="/$repo/"; fi
  : > "$W/cold"
  awk -F'\t' -v c="$col" '$5==c' "$W/docs" | while IFS="$TAB" read -r r ca li id co ti; do
    u=$(url_of "$r" "$ca"); echo "${u#"$BASE"}" >> "$W/cold"
  done
  total=0; direct=0
  while read -r u; do
    total=$((total + 1))
    [ "$u" = "$folder" ] && continue            # documentul care e chiar pagina folderului
    grep -qxF "$u" "$W/hubl" && direct=$((direct + 1))
  done < "$W/cold"
  fara_folder=$(grep -cvxF "$folder" "$W/cold")
  if [ "$direct" -eq 0 ]; then
    if grep -qxF "$folder" "$W/hubl"; then :; else
      problema "$col: nici documentele, nici folderul $folder nu sunt linkuite din hub"; greseli=1
    fi
  elif [ "$direct" -ne "$fara_folder" ]; then
    problema "$col: hub-ul linkuieste direct $direct din $fara_folder fisiere; lipsesc:"
    while read -r u; do
      [ "$u" = "$folder" ] && continue
      grep -qxF "$u" "$W/hubl" || echo "             $BASE$u"
    done < "$W/cold"
    greseli=1
  fi
done
[ "$greseli" -eq 0 ] && ok "fiecare colectie e prezentata complet (document cu document sau prin folder)"

# ════════════════════════════════════════════════════════════════════
titlu 6 "Sitemap-uri: index, liste, realitate"
# ════════════════════════════════════════════════════════════════════

greseli=0
SMI="$HUB/sitemap.xml"
if [ ! -f "$SMI" ]; then problema "lipseste $HUBNAME/sitemap.xml (indexul)"; greseli=1; fi

sm_of() { if [ "$1" = "$HUBNAME" ]; then echo "$HUB/sitemap-hub.xml"; else echo "$RADACINA/$1/sitemap.xml"; fi; }
smurl_of() { if [ "$1" = "$HUBNAME" ]; then echo "$BASE/sitemap-hub.xml"; else echo "$BASE/$1/sitemap.xml"; fi; }

while read -r repo; do
  sm=$(sm_of "$repo")
  if [ ! -f "$sm" ]; then problema "$repo: lipseste ${sm#"$RADACINA"/}"; greseli=1; continue; fi
  if [ -f "$SMI" ] && ! grep -qF "<loc>$(smurl_of "$repo")</loc>" "$SMI"; then
    problema "$repo: sitemap-ul lui nu e in indexul $HUBNAME/sitemap.xml"; greseli=1
  fi
done < "$W/repos"

# fiecare document in sitemap-ul repo-ului sau
while IFS="$TAB" read -r repo cale limba id col tit; do
  sm=$(sm_of "$repo"); [ -f "$sm" ] || continue
  u=$(url_of "$repo" "$cale")
  grep -qF "<loc>$u</loc>" "$sm" || { problema "$id ($limba): $u lipseste din ${sm#"$RADACINA"/}"; greseli=1; }
done < "$W/docs"

# fiecare <loc> din orice sitemap duce la o pagina reala, publica
for sm in "$HUB/sitemap-hub.xml" $(for r in $REPOS_FARA_HUB; do echo "$RADACINA/$r/sitemap.xml"; done); do
  [ -f "$sm" ] || continue
  # toate <loc> de pe fiecare rand (pas55): un sitemap scris pe un singur rand
  # nu mai ascunde adresele de dinaintea ultimei
  awk '{ s = $0; while ((i = index(s, "<loc>")) > 0) { s = substr(s, i + 5); j = index(s, "</loc>"); if (j == 0) break; print substr(s, 1, j - 1); s = substr(s, j + 6) } }' "$sm" | while read -r u; do
    p=${u#"$BASE"}
    seg=${p#/}; seg=${seg%%/*}
    if [ -n "$seg" ] && echo " $REPOS_FARA_HUB " | grep -qF " $seg "; then f="$RADACINA${p}"; else f="$HUB${p}"; fi
    case "$f" in */) f="${f}index.html" ;; esac
    if [ ! -f "$f" ]; then echo "PROBLEMA ${sm#"$RADACINA"/}: $u nu exista pe disc"
    elif e_intern "$f"; then echo "PROBLEMA ${sm#"$RADACINA"/}: $u e marcat noindex"
    fi
  done
done > "$W/smerr"
if [ -s "$W/smerr" ]; then
  while read -r l; do problema "${l#PROBLEMA }"; done < "$W/smerr"; greseli=1
fi
[ "$greseli" -eq 0 ] && ok "indexul, listele fiecarui repo si fisierele de pe disc se potrivesc"

# ════════════════════════════════════════════════════════════════════
titlu 7 "Formulari retrase — supravietuiesc undeva?"
# ════════════════════════════════════════════════════════════════════
# Tiparele: scripts/retrase.txt.  Paginile interne (noindex) au voie sa le citeze.

if [ ! -f "$RETRASE" ]; then
  atentie "lipseste scripts/retrase.txt — verificarea nu ruleaza"
else
  : > "$W/pub"
  while read -r f; do e_intern "$f" || echo "$f" >> "$W/pub"; done < "$W/html"
  while read -r repo; do
    find "$RADACINA/$repo" -name .git -prune -o -type f -name '*.md' -print >> "$W/pub"
  done < "$W/repos"
  grep -v '^#' "$RETRASE" | grep -v '^[[:space:]]*$' > "$W/tipare"
  # textul normalizat al fiecarei pagini, o singura data (pas55)
  mkdir -p "$W/n7"; : > "$W/pubn"
  while read -r f; do
    n="$W/n7/$(echo "${f#"$RADACINA"/}" | sed 's|/|_|g')"
    text_normalizat "$f" > "$n"; printf '%s\t%s\n' "$f" "$n" >> "$W/pubn"
  done < "$W/pub"
  gasit=0
  while read -r tipar; do
    : > "$W/hit"
    # tiparele care contin tag-uri (de ex. „sub 50 de dolari</strong>”) au fost gandite
    # pe marcaj: raman confruntate cu textul brut, ca sa nu devina mai largi
    case "$tipar" in
      *"<"*) while IFS="$TAB" read -r f n; do grep -qF -- "$tipar" "$f" && echo "${f#"$RADACINA"/}" >> "$W/hit"; done < "$W/pubn" ;;
      *)     tn=$(printf '%s' "$tipar" | tr -s ' ')
             while IFS="$TAB" read -r f n; do grep -qF -- "$tn" "$n" && echo "${f#"$RADACINA"/}" >> "$W/hit"; done < "$W/pubn" ;;
    esac
    if [ -s "$W/hit" ]; then
      problema "\"$tipar\" apare in:"; sed 's|^|             |' "$W/hit"; gasit=1
    fi
  done < "$W/tipare"
  [ "$gasit" -eq 0 ] && ok "$(wc -l < "$W/tipare" | tr -d ' ') tipare, nicio formulare retrasa in paginile publice"
fi

# ════════════════════════════════════════════════════════════════════
titlu 8 "Cifrele declarate public == cifrele masurate"
# ════════════════════════════════════════════════════════════════════
# Unde se verifica:  hub index.html + README.md  -> intreg site-ul
#                    pagina si README-ul fiecarei colectii -> colectia
# Cuvinte:  "~N" = rotunjit la mie;  "peste N"/"over N" = rotunjit in jos;
#           N simplu = exact (cine scrie o cifra fara ~ afirma precizie).
# Documentele de lucru (status, context) se compara cu totalul site-ului;
# tabloul din status se verifica rand cu rand, pe colectii.
# Documente: "N documente" / "Seks dokumenter" = numarul de perechi.
# Pe hub, cifrele de documente apar in ordinea colectiilor din manifest.

cat > "$W/nr.awk" <<'AWK'
# Cifrele de documente declarate: cuvantul INTREG dinaintea lui
# "documente"/"dokumenter" (sarind peste "de"), cautat intr-un tabel exact.
# Fara regex cu litere multibyte: unele implementari le citesc octet cu octet.
BEGIN {
  n = split("două:2 Două:2 doua:2 Doua:2 trei:3 Trei:3 patru:4 Patru:4 cinci:5 Cinci:5 " \
            "șase:6 Șase:6 sase:6 Sase:6 șapte:7 Șapte:7 sapte:7 Sapte:7 opt:8 Opt:8 " \
            "nouă:9 Nouă:9 noua:9 Noua:9 zece:10 Zece:10 unsprezece:11 Unsprezece:11 " \
            "douăsprezece:12 Douăsprezece:12 doisprezece:12 Doisprezece:12 " \
            "to:2 To:2 tre:3 Tre:3 fire:4 Fire:4 fem:5 Fem:5 seks:6 Seks:6 sju:7 Sju:7 " \
            "åtte:8 Åtte:8 ni:9 Ni:9 ti:10 Ti:10 elleve:11 Elleve:11 tolv:12 Tolv:12", w, " ")
  for (i = 1; i <= n; i++) { k = w[i]; sub(/:.*/, "", k); v = w[i]; sub(/^.*:/, "", v); nr[k] = v }
}
{
  m = split($0, a)
  for (i = 2; i <= m; i++) {
    x = a[i]; sub(/[.,;:!?]$/, "", x)
    if (x != "documente" && x != "dokumenter") continue
    # cifra: doar imediat inainte ("12 documente") — altfel un an ar fi luat drept numar
    c = a[i - 1]; if (c == "de" && i > 2) c = a[i - 2]
    if (c ~ /^[0-9]+$/) { print c; continue }
    # numeral in litere: pana la 5 cuvinte inapoi, oprit la sfarsit de propozitie
    # ("tolv teologiske, vitenskapelige og geopolitiske dokumenter")
    for (j = i - 1; j >= 1 && j >= i - 5; j--) {
      c = a[j]; g = c; sub(/[,;:]$/, "", g)
      if (g in nr) { print nr[g]; break }
      if (c ~ /[.!?]$/) break
    }
  }
}
AWK

RE_CUV='(~|peste |over )?[0-9]{1,3}([. ][0-9]{3})+( de)? (cuvinte|ord)'
# textul fara tag-uri, cu ghilimelele si parantezele transformate in spatii
decl_docs() {
  sed 's/<[^>]*>/ /g; s/&nbsp;/ /g; s/[("*>]/ /g; s/„/ /g; s/”/ /g; s/«/ /g; s/»/ /g' "$1" | LC_ALL=C sed "s/$NBSP/ /g" | awk -f "$W/nr.awk"
}

rot()  { echo $(( ($1 + 500) / 1000 * 1000 )); }
jos()  { echo $(( $1 / 1000 * 1000 )); }

verifica_cuv() {   # <fisier> <valoare-masurata> <eticheta>
  # pe textul normalizat (pas55): „181&nbsp;000 ord” sau o cifra rupta de un tag
  # nu mai scapa nevazute
  text_normalizat "$1" | grep -oE "$RE_CUV" 2>/dev/null | while read -r dec; do
    cifre=$(echo "$dec" | sed 's/ de cuvinte//; s/ cuvinte//; s/ ord//' | tr -cd '0-9')
    case "$dec" in peste*|over*) tinta=$(jos "$2"); fel="rotunjit in jos" ;;
                   "~"*)         tinta=$(rot "$2"); fel="rotunjit" ;;
                   *)            tinta=$2;          fel="exact" ;; esac
    if [ "$cifre" -eq "$tinta" ]; then echo "OK"
    else echo "PROBLEMA ${1#"$RADACINA"/} declara \"$dec\"; $3 masurat $2 ($fel: $tinta)"; fi
  done
}

cuv_col() { awk -F'\t' -v c="$1" '$1==c {s += $3} END {print s + 0}' "$W/cuv"; }
doc_col() { awk -F'\t' -v c="$1" '$2==c' "$W/m" | wc -l | tr -d ' '; }

: > "$W/nrerr"; : > "$W/nrok"
# site
for f in "$HUB/index.html" "$HUB/README.md"; do
  [ -f "$f" ] || continue
  verifica_cuv "$f" "$TOTAL_CUV" "site-ul intreg:" >> "$W/nrerr"
  decl_docs "$f" > "$W/decl"
  cut -f2 "$W/m" | awk '!s[$0]++' | while read -r c; do doc_col "$c"; done > "$W/real"
  n=$(wc -l < "$W/decl" | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    head -n "$n" "$W/real" > "$W/real_n"
    if cmp -s "$W/decl" "$W/real_n"; then echo OK >> "$W/nrerr"
    else echo "PROBLEMA ${f#"$RADACINA"/}: documente declarate [$(tr '\n' ' ' < "$W/decl")] in ordinea colectiilor, manifestul are [$(tr '\n' ' ' < "$W/real_n")]" >> "$W/nrerr"; fi
  fi
done
# fiecare colectie
for col in $(cut -f2 "$W/m" | awk '!s[$0]++'); do
  repo=$(awk -F'\t' -v c="$col" '$2==c {print $3; exit}' "$W/m")
  if [ "$repo" = "$HUBNAME" ]; then fis="$HUB/$col/index.html"
  else fis="$RADACINA/$repo/index.html $RADACINA/$repo/README.md"; fi
  for f in $fis; do
    [ -f "$f" ] || continue
    verifica_cuv "$f" "$(cuv_col "$col")" "colectia $col:" >> "$W/nrerr"
    real=$(doc_col "$col")
    decl_docs "$f" | while read -r d; do
      if [ "$d" = "$real" ]; then echo OK
      else echo "PROBLEMA ${f#"$RADACINA"/} declara $d documente; colectia $col are $real (perechi RO+NO)"; fi
    done >> "$W/nrerr"
  done
done
# documentele de lucru din hub: orice cifra se compara cu totalul site-ului
TOTAL_DOC=$(wc -l < "$W/m" | tr -d ' ')
for f in "$HUB/status-proiect.html" "$HUB/context-sesiune.html"; do
  [ -f "$f" ] || continue
  verifica_cuv "$f" "$TOTAL_CUV" "site-ul intreg:" >> "$W/nrerr"
  decl_docs "$f" | while read -r d; do
    if [ "$d" = "$TOTAL_DOC" ]; then echo OK
    else echo "PROBLEMA ${f#"$RADACINA"/} declara $d documente; manifestul are $TOTAL_DOC"; fi
  done >> "$W/nrerr"
done

# tabloul din status: un rand pe colectie + TOTAL, fiecare verificat
STATUS="$HUB/status-proiect.html"
if [ -f "$STATUS" ]; then
  sed -n 's|.*<tr data-colectie="\([^"]*\)"><td>.*</td><td>\([0-9]*\)</td><td>~\([0-9.]*\)</td></tr>.*|\1 \2 \3|p' "$STATUS" > "$W/st"
  for col in $(cut -f2 "$W/m" | awk '!s[$0]++') TOTAL; do
    linie=$(awk -v c="$col" '$1==c' "$W/st")
    if [ -z "$linie" ]; then echo "PROBLEMA status-proiect.html: tabloul nu are rand pentru $col"; continue; fi
    set -- $linie
    if [ "$col" = TOTAL ]; then rd=$TOTAL_DOC; rc=$TOTAL_CUV; else rd=$(doc_col "$col"); rc=$(cuv_col "$col"); fi
    if [ "$2" = "$rd" ]; then echo OK
    else echo "PROBLEMA status-proiect.html: tabloul spune $2 documente la $col; manifestul are $rd"; fi
    c=$(echo "$3" | tr -cd '0-9')
    if [ "$c" -eq "$(rot "$rc")" ]; then echo OK
    else echo "PROBLEMA status-proiect.html: tabloul spune ~$3 cuvinte la $col; masurat $rc (rotunjit: $(rot "$rc"))"; fi
  done >> "$W/nrerr"
  awk '{print $1}' "$W/st" | while read -r c; do
    [ "$c" = TOTAL ] && continue
    cut -f2 "$W/m" | grep -qxF "$c" || echo "PROBLEMA status-proiect.html: tabloul are rand pentru $c, care nu e in manifest"
  done >> "$W/nrerr"
else
  echo "PROBLEMA lipseste $HUBNAME/status-proiect.html — tabloul de continuitate" >> "$W/nrerr"
fi

nok=$(grep -c '^OK' "$W/nrerr")
grep '^PROBLEMA' "$W/nrerr" | sort -u | while read -r l; do echo "${l#PROBLEMA }"; done > "$W/nrp"
if [ -s "$W/nrp" ]; then while read -r l; do problema "$l"; done < "$W/nrp"; fi
[ ! -s "$W/nrp" ] && ok "$nok declaratii verificate, toate corespund masuratorii"
[ -s "$W/nrp" ] && [ "$nok" -gt 0 ] && ok "$nok declaratii corespund"

# ════════════════════════════════════════════════════════════════════
titlu 9 "Structura HTML a documentelor"
# ════════════════════════════════════════════════════════════════════

greseli=0
while IFS="$TAB" read -r repo cale limba id col tit; do
  f="$RADACINA/$repo/$cale"; [ -f "$f" ] || continue
  dez=""
  # din pas55 si tag-urile de text: un <em> sau un <a> neinchis colora sau lega
  # tot restul paginii, nevazut (asa a stat un </em> ratacit in Firul Rosu A)
  for tag in html head body section blockquote div p a em strong span ul ol li h1 h2 h3 h4 table tr td th nav header footer main article aside figure pre code; do
    d=$(awk -F'\t' -v t="$tag" '$1==t' "$(tagsf "$f")" | wc -l | tr -d ' ')
    i=$(grep -o "</$tag>" "$f" | wc -l | tr -d ' ')
    [ "$d" = "$i" ] || dez="$dez $tag($d/$i)"
  done
  [ -n "$dez" ] && { problema "$repo/$cale dezechilibrat:$dez"; greseli=1; }
  grep -q '">n<' "$f" && { problema "$repo/$cale: artefact '\">n<' (newline pierdut de sed BSD)"; greseli=1; }
done < "$W/docs"
[ "$greseli" -eq 0 ] && ok "tag-uri echilibrate, niciun artefact sed"

# ════════════════════════════════════════════════════════════════════
titlu 10 "ADN-ul fiecarui repo: fisiere de baza si garda pre-push"
# ════════════════════════════════════════════════════════════════════

REF_HOOK="$HUB/scripts/hooks/pre-push"
REF_WF="$HUB/.github/workflows/verifica.yml"
ref_wf=""; [ -f "$REF_WF" ] && ref_wf=$(cksum < "$REF_WF")
REF_LIC="$HUB/LICENSE"
ref_lic=""; [ -f "$REF_LIC" ] && ref_lic=$(cksum < "$REF_LIC")
if [ -f "$REF_LIC" ] && ! grep -qF "Creative Commons Attribution 4.0 International Public License" "$REF_LIC"; then
  problema "$HUBNAME/LICENSE nu e textul oficial CC BY 4.0 — GitHub nu-l poate recunoaste"
fi
# sectiunea de licenta din README: identica peste tot (de la titlu pana la marcaj)
bloc_lic() { sed -n '/^## Licență · Lisens$/,/^<!-- sfarsit licenta -->$/p' "$1"; }
ref_bloc=""; [ -f "$HUB/README.md" ] && ref_bloc=$(bloc_lic "$HUB/README.md" | cksum)
ref_sum=""; [ -f "$REF_HOOK" ] && ref_sum=$(cksum < "$REF_HOOK")
greseli=0
while read -r repo; do
  d="$RADACINA/$repo"; [ -d "$d" ] || continue
  lipsa=""
  for x in README.md LICENSE .gitignore .nojekyll; do [ -f "$d/$x" ] || lipsa="$lipsa $x"; done
  [ "$repo" = "$HUBNAME" ] && for x in robots.txt 404.html sitemap.xml sitemap-hub.xml; do [ -f "$d/$x" ] || lipsa="$lipsa $x"; done
  [ -n "$lipsa" ] && { problema "$repo: lipseste$lipsa"; greseli=1; }

  # radacina: doar ce e permis. Fisierele-fantoma (main pe 15 sept,
  # FETCH_HEAD pe 27 sept) apar din comenzi taiate la lipire; comise, raman.
  dirs_ok=$(awk -F'\t' -v r="$repo" '$3==r {print $4; print $5}' "$W/m" | sed -n 's|/.*||p' | sort -u | tr '\n' ' ')
  for x in "$d"/* "$d"/.[!.]*; do
    [ -e "$x" ] || continue
    b=$(basename "$x")
    case "$b" in
      .git|.github|.gitignore|.nojekyll|LICENSE|README.md|sitemap.xml|scripts|*.html) continue ;;
    esac
    if [ "$repo" = "$HUBNAME" ]; then
      case "$b" in robots.txt|sitemap-hub.xml|asculta.js) continue ;; esac
    fi
    if [ -d "$x" ] && echo " $dirs_ok " | grep -qF " $b "; then continue; fi
    problema "$repo: \"$b\" nu are ce cauta in radacina (fisier-fantoma sau uitat?)"; greseli=1
  done

  if [ -f "$d/LICENSE" ] && [ "$(cksum < "$d/LICENSE")" != "$ref_lic" ]; then
    problema "$repo: LICENSE difera de cea din hub (trebuie identice, textul oficial)"; greseli=1
  fi
  if [ -f "$d/README.md" ]; then
    if [ -z "$(bloc_lic "$d/README.md")" ]; then
      problema "$repo: README.md nu are sectiunea \"## Licență · Lisens\" (cu marcajul de sfarsit)"; greseli=1
    elif [ "$(bloc_lic "$d/README.md" | cksum)" != "$ref_bloc" ]; then
      problema "$repo: sectiunea de licenta din README difera de cea din hub"; greseli=1
    fi
  fi
  # a doua plasa: workflow-ul CI, identic peste tot
  if [ ! -f "$d/.github/workflows/verifica.yml" ]; then
    problema "$repo: nu are .github/workflows/verifica.yml (CI)"; greseli=1
  elif [ "$(cksum < "$d/.github/workflows/verifica.yml")" != "$ref_wf" ]; then
    problema "$repo: workflow-ul CI difera de cel din hub (trebuie identice)"; greseli=1
  fi


  h="$d/scripts/hooks/pre-push"
  if [ ! -f "$h" ]; then problema "$repo: nu are scripts/hooks/pre-push"; greseli=1
  else
    [ -x "$h" ] || { problema "$repo: hook-ul nu e executabil"; greseli=1; }
    [ "$(cksum < "$h")" = "$ref_sum" ] || { problema "$repo: hook-ul difera de cel din hub (trebuie identice)"; greseli=1; }
  fi
  # ce urmeaza tine de clona locala — in CI nu exista, deci nu se verifica acolo
  if [ "$MOD" != ci ]; then
    hp=$(git -C "$d" config --get core.hooksPath 2>/dev/null)
    [ "$hp" = "scripts/hooks" ] || { problema "$repo: garda inactiva (core.hooksPath=\"${hp:-nesetat}\")"; greseli=1; }
    # identitatea cu care se fac commit-urile: adresa noreply, nu emailul personal
    em=$(git -C "$d" config --get user.email 2>/dev/null)
    case "$em" in
      *@users.noreply.github.com) ;;
      *) problema "$repo: commit-urile s-ar face cu <${em:-nesetat}> — trebuie adresa noreply GitHub"; greseli=1 ;;
    esac
    # push-ul prin SSH (cheie cu parola), nu prin HTTPS cu token in text clar
    pu=$(git -C "$d" remote get-url --push origin 2>/dev/null)
    [ "$pu" = "git@github.com:norgedan/$repo.git" ] || { problema "$repo: push-ul merge spre \"${pu:-nimic}\" — trebuie git@github.com:norgedan/$repo.git (SSH)"; greseli=1; }
  fi

  for v in scripts/verifica.sh scripts/verifica-hub.sh; do
    [ -f "$d/$v" ] && { problema "$repo: $v inca exista — verificarea trebuie sa aiba o singura sursa"; greseli=1; }
  done
done < "$W/repos"
if [ "$MOD" != ci ]; then
  ch=$(git config --global --get credential.helper 2>/dev/null)
  [ -n "$ch" ] && atentie "credential.helper=\"$ch\" — parolele/tokenurile s-ar salva din nou pe disc; push-ul merge prin SSH"
fi
[ "$greseli" -eq 0 ] && ok "toate repo-urile au fisierele de baza si aceeasi garda activa"

# ════════════════════════════════════════════════════════════════════
titlu 11 "Starea git: ce verific e ce se publica"
# ════════════════════════════════════════════════════════════════════
# Mod manual:  doar ATENTIE (esti in mijlocul lucrului), fara retea.
# Mod --push:  arbori curati obligatoriu; nimic in urma fata de GitHub;
#              commit-uri nepublicate in alte repo-uri = ATENTIE.

greseli=0
[ "$MOD" = ci ] && echo "  (sarit in CI — starea clonelor locale nu exista pe server)"
[ "$MOD" = ci ] || while read -r repo; do
  d="$RADACINA/$repo"; [ -d "$d/.git" ] || continue
  br=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$br" = "main" ] || { problema "$repo: pe ramura \"$br\", nu pe main"; greseli=1; continue; }
  if [ -n "$(git -C "$d" status --porcelain)" ]; then
    if [ "$MOD" = push ]; then problema "$repo: modificari necomise — verificarea n-ar vedea ce se publica"; greseli=1
    else atentie "$repo: modificari necomise (inainte de push trebuie comise)"; fi
  fi
  if [ "$MOD" = push ]; then
    git -C "$d" fetch -q origin 2>/dev/null || { problema "$repo: nu pot aduce starea de pe GitHub"; greseli=1; continue; }
  fi
  git -C "$d" rev-parse -q --verify origin/main >/dev/null || continue
  urma=$(git -C "$d" rev-list --count HEAD..origin/main)
  ainte=$(git -C "$d" rev-list --count origin/main..HEAD)
  if [ "$urma" -gt 0 ]; then
    if [ "$MOD" = push ]; then problema "$repo: $urma commit(uri) pe GitHub pe care clona nu le are — git pull"; greseli=1
    else atentie "$repo: in urma cu $urma commit(uri) la ultima aducere — git pull"; fi
  fi
  if [ "$ainte" -gt 0 ] && [ "$repo" != "$PUSH_REPO" ]; then
    atentie "$repo: $ainte commit(uri) nepublicate — publica-le si pe ele, altfel site-ul live ramane incoerent"
  fi
done < "$W/repos"
# ce pleaca spre main trebuie sa fie exact HEAD-ul verificat (pas55): altfel un
# „git push origin alta-ramura:main” ar publica un commit pe care verificarea nu l-a vazut
if [ "$MOD" = push ] && [ -s "$W/pushin" ]; then
  cap=$(git -C "$RADACINA/$PUSH_REPO" rev-parse HEAD 2>/dev/null)
  while read -r lref lsha rref rsha; do
    [ "$rref" = refs/heads/main ] || continue
    case "$lsha" in
      *[!0]*) [ "$lsha" = "$cap" ] || { problema "$PUSH_REPO: spre main pleaca $(echo "$lsha" | cut -c1-7), dar verificarea a vazut HEAD $(echo "$cap" | cut -c1-7) — push doar din HEAD: git push"; greseli=1; } ;;
      *)      problema "$PUSH_REPO: push-ul ar sterge ramura main de pe GitHub"; greseli=1 ;;
    esac
  done < "$W/pushin"
fi
[ "$greseli" -eq 0 ] && ok "nicio clona in urma fata de GitHub; arborii verificati sunt cei care se publica"

# Jurnalul privat (din 20 oct 2026): DOCUMENTARE.md nu se scrie automat — hotararile
# si motivele nu le stie masina — dar nu are voie sa ramana in urma nevazut.
# Doar local (in CI repo-ul privat nu exista si nu trebuie sa existe); citeste doar
# DATELE din tabelul „Istoricul acestui document” (randuri "| AAAA-LL-ZZ |"), nu
# continutul.  Din pas68: jurnalul trebuie sa pomeneasca ultimul pas din hub (pasNN).
JURNAL="${NORGEDAN_JURNAL:-$RADACINA/norgedan-jurnal}"
if [ "$MOD" != ci ] && [ "$MOD" != tablou ]; then
  if [ ! -f "$JURNAL/DOCUMENTARE.md" ]; then
    atentie "nu gasesc $JURNAL/DOCUMENTARE.md — jurnalul proiectului nu poate fi urmarit"
  else
    jd=$(grep -o '^| 20[0-9][0-9]-[01][0-9]-[0-3][0-9] |' "$JURNAL/DOCUMENTARE.md" | tr -d '| ' | sort | tail -1)
    # Din pas68: nu se mai compara datele — un pas comis dupa miezul noptii parea „in urma”
    # desi jurnalul era la zi.  Se cauta numele pasului (cuvant intreg) in jurnal.
    # (Pas64: subiectul se ia separat, fara ${hp#*|}, care nu merge pe ksh-ul OpenBSD.)
    hs=$(git -C "$HUB" log -1 --grep='^pas[0-9]' --format='%s' 2>/dev/null | cut -d: -f1)
    if [ -z "$jd" ]; then
      atentie "DOCUMENTARE.md nu are nicio data in „Istoricul acestui document” — nu se poate spune daca e la zi"
    elif [ -n "$hs" ] && ! grep -q -w -- "$hs" "$JURNAL/DOCUMENTARE.md"; then
      atentie "DOCUMENTARE.md a ramas in urma: ultimul pas din hub ($hs) nu apare in jurnal (ultima intrare: $jd) — de adus la zi in norgedan-jurnal"
    fi
    if [ -d "$JURNAL/.git" ]; then
      [ -n "$(git -C "$JURNAL" status --porcelain)" ] && atentie "norgedan-jurnal: modificari necomise"
      if git -C "$JURNAL" rev-parse -q --verify origin/main >/dev/null; then
        jn=$(git -C "$JURNAL" rev-list --count origin/main..HEAD)
        [ "$jn" -gt 0 ] && atentie "norgedan-jurnal: $jn commit(uri) neimpinse pe GitHub (repo-ul privat e copia de siguranta)"
      fi
    fi
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 12 "Pagina GitHub a fiecarui repo (About) == scripts/about.tsv"
# ════════════════════════════════════════════════════════════════════
# Descrierea, website-ul si topics se vad primele pe GitHub.  Au continut
# cifra retrasa "~220.000" timp de 9 zile, nevazute de nicio verificare.
# Retea: doar la push si cu --github.  API indisponibil = ATENTIE, nu blocaj.

api_get() {   # <repo> <fisier>
  if [ -n "${NORGEDAN_API_DIR:-}" ]; then cp "$NORGEDAN_API_DIR/$1.json" "$2" 2>/dev/null; return; fi
  u="https://api.github.com/repos/norgedan/$1"
  if command -v curl >/dev/null 2>&1; then
    # in GitHub Actions: tokenul automat, fara limita de 60 de cereri/ora
    if [ -n "${GITHUB_TOKEN:-}" ]; then curl -fsS -H "Authorization: Bearer $GITHUB_TOKEN" -o "$2" "$u" 2>/dev/null
    else curl -fsS -o "$2" "$u" 2>/dev/null; fi
  else ftp -V -o "$2" "$u" >/dev/null 2>&1; fi
}
# GitHub trimite JSON compact unor clienti (ftp) si formatat altora (curl):
# "cheie":"v" sau "cheie": "v", liste pe o linie sau pe mai multe.
# De aceea: tot fisierul pe o singura linie, spatii permise in jurul lui ":".
json_1l()  { tr '\n\r' '  ' < "$1"; }
json_str() { json_1l "$2" | grep -o "\"$1\"[ ]*:[ ]*\"[^\"]*\"" | head -1 | sed "s/^\"$1\"[ ]*:[ ]*\"//; s/\"\$//"; }
json_bool() { json_1l "$2" | grep -o "\"$1\"[ ]*:[ ]*[a-z]*" | head -1 | sed "s/^\"$1\"[ ]*:[ ]*//"; }
topics_of() { json_1l "$1" | grep -o '"topics"[ ]*:[ ]*\[[^]]*\]' | sed 's/^"topics"[ ]*:[ ]*\[//; s/\]$//; s/[" ]//g' | tr ',' '\n' | grep -v '^$' | sort | tr '\n' ','; }

if [ "$MOD" != push ] && [ "$MOD" != github ] && [ "$MOD" != ci ]; then
  echo "  (sarit fara retea — ruleaza cu --github; la push ruleaza singur)"
elif [ ! -f "$ABOUT" ]; then
  problema "lipseste scripts/about.tsv — sursa paginilor GitHub"
else
  grep -v '^#' "$ABOUT" | grep -v '^[[:space:]]*$' > "$W/about"
  greseli=0; npg=0; nramura=0; ncitite=0
  while read -r repo; do
    linie=$(awk -F'\t' -v r="$repo" '$1==r' "$W/about")
    if [ -z "$linie" ]; then problema "$repo: nu are rand in scripts/about.tsv"; greseli=1; continue; fi
    printf '%s\n' "$linie" | awk -F'\t' 'NF!=4 {exit 1}' || { problema "$repo: randul din about.tsv nu are 4 coloane"; greseli=1; continue; }
    d_ok=$(printf '%s\n' "$linie" | cut -f2); w_ok=$(printf '%s\n' "$linie" | cut -f3)
    t_ok=$(printf '%s\n' "$linie" | cut -f4 | tr ',' '\n' | grep -v '^$' | sort | tr '\n' ',')
    if ! api_get "$repo" "$W/api.json" || ! grep -q '"full_name"' "$W/api.json"; then
      atentie "$repo: pagina GitHub nu poate fi citita acum (retea sau limita API) — verificare sarita"; continue
    fi
    ncitite=$((ncitite + 1))
    d=$(json_str description "$W/api.json"); w=$(json_str homepage "$W/api.json"); t=$(topics_of "$W/api.json")
    [ "$d" = "$d_ok" ] || { problema "$repo: descrierea de pe GitHub difera de about.tsv"; echo "             GitHub:    ${d:-(goala)}"; echo "             about.tsv: $d_ok"; greseli=1; }
    [ "$w" = "$w_ok" ] || { problema "$repo: website-ul de pe GitHub e \"${w:-gol}\", trebuie $w_ok"; greseli=1; }
    [ "$t" = "$t_ok" ] || { problema "$repo: topics pe GitHub [${t%,}], trebuie [${t_ok%,}]"; greseli=1; }
    for f in has_wiki has_projects; do
      [ "$(json_bool $f "$W/api.json")" = "false" ] || { problema "$repo: ${f#has_} activ pe GitHub, dar nefolosit — Settings, Features"; greseli=1; }
    done
    # publicarea: doar prin GitHub Actions, adica doar dupa jobul "verifica"
    # (build_type "legacy" = Pages publica direct din ramura, ocolind verificarea).
    # Doar cu token (in GitHub Actions): fara token, GitHub nu arata sursa
    # publicarii, iar cererea in plus ar consuma limita de 60 de cereri/ora.
    if [ -n "${GITHUB_TOKEN:-}${NORGEDAN_API_DIR:-}" ] && api_get "$repo/pages" "$W/pages.json" && grep -q '"build_type"' "$W/pages.json"; then
      npg=$((npg + 1)); bt=$(json_str build_type "$W/pages.json")
      if [ "$bt" != workflow ]; then
        nramura=$((nramura + 1))
        atentie "$repo: GitHub Pages publica direct din ramura (\"$bt\"), ocolind verificarea — Settings, Pages, Source: GitHub Actions"
      fi
    fi
    sp=$(json_str spdx_id "$W/api.json")
    [ "$sp" = "CC-BY-4.0" ] || atentie "$repo: GitHub vede licenta ca \"${sp:-nimic}\" — daca LICENSE tocmai s-a schimbat, GitHub o recalculeaza dupa push"
  done < "$W/repos"
  awk -F'\t' '{print $1}' "$W/about" | while read -r r; do
    grep -qxF "$r" "$W/repos" || echo "$r"
  done > "$W/aboutx"
  while read -r r; do problema "about.tsv are rand pentru $r, care nu e repo al site-ului"; greseli=1; done < "$W/aboutx"
  [ "$greseli" -eq 0 ] && [ "$ncitite" -gt 0 ] && ok "paginile GitHub corespund about.tsv (descriere, website, topics, fara wiki/projects) — $ncitite din $(wc -l < "$W/repos" | tr -d ' ') citite"
  [ "$npg" -gt 0 ] && [ "$nramura" -eq 0 ] && ok "publicarea trece prin verificare (GitHub Actions) in toate cele $npg repo-uri citite"
fi

# ════════════════════════════════════════════════════════════════════
titlu 13 "Afirmatiile: registru, perechi RO-NO, datoria de verificare"
# ════════════════════════════════════════════════════════════════════
# Sectiunile 1-12 verifica forma.  Aceasta tine evidenta faptelor: nu poate
# judeca adevarul, dar nu lasa nicio afirmatie fara eticheta, sursa si decizie.
#   scripts/afirmatii.tsv         registrul (formatul: in capul fisierului)
#   <span data-afirmatie="id">    afirmatia, marcata pe locul ei, in RO si in NO
#   scripts/certitudini.txt       cuvinte de certitudine cautate in textul nemarcat
#   scripts/certitudini-ok.txt    fragmente citite si acceptate
# PROBLEMA doar pentru ce masina judeca sigur: registru stricat, id necunoscut
# sau nefolosit, marcaj pe alt tag, afirmatie prezenta intr-o singura limba.
# Datoria de verificare si detectorul = ATENTIE: amandoua cer judecata umana.

# paginile publice (fara noindex), ca la [7]
: > "$W/pub13"
while read -r f; do e_intern "$f" || echo "$f" >> "$W/pub13"; done < "$W/html"

# marcajele din pagini, citite din tag-uri reale:  id TAB fisier TAB tag
: > "$W/afuz"
while read -r f; do
  awk -F'\t' -v r="${f#"$RADACINA"/}" \
    '{for (i = 2; i < NF; i += 2) if ($i == "data-afirmatie") print $(i + 1) "\t" r "\t" $1}' \
    "$(tagsf "$f")" >> "$W/afuz"
done < "$W/pub13"

greseli=0
: > "$W/af"
if [ ! -f "$AFIRMATII" ]; then
  atentie "lipseste scripts/afirmatii.tsv — registrul nu poate fi verificat"
else
  grep -v '^#' "$AFIRMATII" | grep -v '^[[:space:]]*$' > "$W/af"
  awk -F'\t' '
    NF != 8 { print "rand " NR ": " NF " coloane, trebuie 8"; next }
    {
      for (i = 1; i <= 8; i++) if ($i == "") print "rand " NR ": coloana " i " e goala (fara continut se scrie -)"
      if ($8 != "-" && $8 !~ /^[0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]$/) print $1 ": reverifica \"" $8 "\" — trebuie AAAA-LL-ZZ sau -"
      if ($1 !~ /^[a-z0-9][a-z0-9-]*$/) print "rand " NR ": id \"" $1 "\" — doar litere mici fara diacritice, cifre si -"
      if (id[$1]++) print "id duplicat: " $1
      if ($2 != "FAPT" && $2 != "ESTIMARE" && $2 != "INTERPRETARE" && $2 != "CREDINTA")
        print $1 ": eticheta \"" $2 "\" — trebuie FAPT, ESTIMARE, INTERPRETARE sau CREDINTA"
      if ($3 != "verificat" && $3 != "de-verificat" && $3 != "de-corectat")
        print $1 ": stare \"" $3 "\" — trebuie verificat, de-verificat sau de-corectat"
      if ($3 == "verificat" && $2 != "CREDINTA" && $5 == "-") print $1 ": e verificat, dar nu are sursa"
      if ($3 == "verificat" && ($2 == "FAPT" || $2 == "ESTIMARE") && $6 == "-") print $1 ": e verificat, dar nu are anul sursei"
    }' "$W/af" > "$W/aferr"
  while read -r l; do problema "afirmatii.tsv: $l"; greseli=1; done < "$W/aferr"
fi
cut -f1 "$W/af" | LC_ALL=C sort -u > "$W/afid"
cut -f1 "$W/afuz" | LC_ALL=C sort -u > "$W/afuzid"

# marcajul se pune doar pe <span>: altfel detectorul nu-l poate ocoli corect
awk -F'\t' '$3 != "span" {print $2 ": data-afirmatie=\"" $1 "\" pe <" $3 "> — se pune doar pe <span>"}' "$W/afuz" > "$W/x13"
while read -r l; do problema "$l"; greseli=1; done < "$W/x13"

# id marcat in pagina, dar absent din registru
while read -r i; do
  grep -qxF -- "$i" "$W/afid" && continue
  problema "data-afirmatie=\"$i\" nu exista in afirmatii.tsv — in: $(awk -F'\t' -v i="$i" '$1==i {print $2}' "$W/afuz" | sort -u | tr '\n' ' ')"
  greseli=1
done < "$W/afuzid"

# rand in registru, dar nemarcat nicaieri: afirmatia a disparut sau marcajul s-a pierdut
while read -r i; do
  grep -qxF -- "$i" "$W/afuzid" && continue
  problema "afirmatii.tsv: \"$i\" nu e marcat in nicio pagina publica — marcheaza-l sau sterge randul"
  greseli=1
done < "$W/afid"

# perechile: ce e marcat in RO e marcat si in NO, cu acelasi id
: > "$W/afpar"
while IFS="$TAB" read -r id col repo cro cno tro tno; do
  awk -F'\t' -v r="$repo/$cro" '$2==r {print $1}' "$W/afuz" | LC_ALL=C sort -u > "$W/afro"
  awk -F'\t' -v r="$repo/$cno" '$2==r {print $1}' "$W/afuz" | LC_ALL=C sort -u > "$W/afno"
  # diferenta de multimi cu awk (fara comm; corect si cand un fisier e gol)
  awk -v A="$W/afno" 'BEGIN {while ((getline l < A) > 0) a[l] = 1} !($0 in a)' "$W/afro" \
    | sed "s|^|$id: \"|; s|\$|\" marcat in RO, lipseste in NO ($repo/$cno)|" >> "$W/afpar"
  awk -v A="$W/afro" 'BEGIN {while ((getline l < A) > 0) a[l] = 1} !($0 in a)' "$W/afno" \
    | sed "s|^|$id: \"|; s|\$|\" marcat in NO, lipseste in RO ($repo/$cro)|" >> "$W/afpar"
done < "$W/m"
while read -r l; do problema "$l"; greseli=1; done < "$W/afpar"

# Amprentele (pas54): textul unei afirmatii verificate e inghetat.  Pentru fiecare
# marcaj, pe fiecare pagina publica: cksum pe textul dintre <span data-afirmatie>
# si </span>, fara tag-uri, cu spatiile unificate.  scripts/amprente.tsv tine
# perechile (id, fisier) cu amprenta lor.  Blocheaza:
#   - textul s-a schimbat dupa verificare        -> reverifica la sursa, apoi --amprente
#   - marcaj nou sau mutat (id refolosit in alt document) -> idem
#   - amprenta fara marcaj (marcajul a disparut)  -> idem
# Un id e astfel legat de documentele lui: nu poate acoperi alt text, altundeva.
cat > "$W/ampr.awk" <<'AWK'
BEGIN { RS = "\001"; M = "<span data-afirmatie=\"" }
{
  s = $0
  while ((i = index(s, M)) > 0) {
    s = substr(s, i + length(M)); q = index(s, "\""); if (q == 0) break
    id = substr(s, 1, q - 1)
    g = index(s, ">"); if (g == 0) break
    s = substr(s, g + 1); j = index(s, "</span>"); if (j == 0) break
    t = substr(s, 1, j - 1); s = substr(s, j + 7)
    gsub(/<[^>]*>/, " ", t); gsub(/&nbsp;/, " ", t); gsub(/[ \t\r\n]+/, " ", t)
    sub(/^ /, "", t); sub(/ $/, "", t)
    print id "\t" t
  }
}
AWK
: > "$W/amprn"
while read -r f; do
  rel=${f#"$RADACINA"/}
  LC_ALL=C awk -f "$W/ampr.awk" "$f" | while IFS="$TAB" read -r id txt; do
    printf '%s\t%s\t%s\n' "$id" "$rel" "$(printf '%s' "$txt" | cksum | awk '{print $1 "-" $2}')"
  done >> "$W/amprn"
done < "$W/pub13"
LC_ALL=C sort "$W/amprn" > "$W/amprs"

if [ "$MOD" = amprente ]; then
  {
    echo "# amprente.tsv — amprentele afirmatiilor verificate (verifica-site.sh [13], din pas54)."
    echo "# Un rand = un marcaj <span data-afirmatie> pe o pagina publica:  id TAB fisier TAB cksum"
    echo "# cksum: suma si lungimea textului din marcaj, fara tag-uri, cu spatiile unificate."
    echo "# NU se editeaza de mana.  Dupa ce o afirmatie a fost (re)verificata la sursa:"
    echo "#   sh ~/norgedan.github.io/scripts/verifica-site.sh --amprente"
    echo "# si diferenta (git diff scripts/amprente.tsv) se citeste inainte de commit."
    cat "$W/amprs"
  } > "$AMPRENTE"
  echo ""
  echo "  amprente.tsv rescris: $(wc -l < "$W/amprs" | tr -d ' ') marcaje.  Citeste diferenta inainte de commit:"
  echo "    git -C $HUB diff --stat scripts/amprente.tsv"
  echo ""
  exit 0
fi

if [ ! -f "$AMPRENTE" ]; then
  problema "lipseste scripts/amprente.tsv — dupa verificarea afirmatiilor: sh $0 --amprente"; greseli=1
else
  grep -v '^#' "$AMPRENTE" | grep -v '^[[:space:]]*$' | LC_ALL=C sort > "$W/ampro"
  # aceeasi pereche (id, fisier): amprenta schimbata = text schimbat
  awk -F'\t' -v A="$W/ampro" '
    BEGIN { while ((getline l < A) > 0) { split(l, x, "\t"); v[x[1] "\t" x[2]] = x[3] } }
    { k = $1 "\t" $2; vazut[k] = 1
      if (!(k in v)) print "marcaj fara amprenta: \"" $1 "\" in " $2 " — afirmatie noua sau mutata (un id e legat de documentele lui); dupa verificarea la sursa: --amprente"
      else if (v[k] != $3) print "\"" $1 "\" in " $2 ": textul afirmatiei s-a schimbat dupa verificare — reverifica la sursa, apoi --amprente" }
    END { for (k in v) if (!(k in vazut)) { split(k, x, "\t"); print "amprenta fara marcaj: \"" x[1] "\" in " x[2] " — marcajul a disparut; dupa verificare: --amprente" } }
  ' "$W/amprs" | LC_ALL=C sort > "$W/amprerr"
  while IFS= read -r l; do problema "$l"; greseli=1; done < "$W/amprerr"
fi

if [ "$greseli" -eq 0 ]; then
  n=$(wc -l < "$W/af" | tr -d ' ')
  if [ "$n" -eq 0 ]; then ok "registrul e gol — nicio afirmatie marcata inca"
  else ok "$n afirmatii in registru, toate marcate, perechile RO-NO intregi; $(wc -l < "$W/amprs" | tr -d ' ') marcaje cu amprenta neschimbata"; fi
fi

# datoria de verificare: vizibila la fiecare rulare, fara sa blocheze lucrul
nv=$(awk -F'\t' '$3=="de-verificat"' "$W/af" | wc -l | tr -d ' ')
nc=$(awk -F'\t' '$3=="de-corectat"' "$W/af" | wc -l | tr -d ' ')
if [ "$nv" -gt 0 ] || [ "$nc" -gt 0 ]; then
  atentie "datoria de verificare: $nv de verificat, $nc de corectat"
  awk -F'\t' '$3=="de-corectat" || $3=="de-verificat" {print "             " $3 ": " $1}' "$W/af"
fi

# faptele care se invechesc: data de reverificare a trecut
AZI=$(date +%Y-%m-%d)
awk -F'\t' -v azi="$AZI" '$8 != "-" && $8 <= azi {print $1 " (pana la " $8 ")"}' "$W/af" > "$W/afexp"
if [ -s "$W/afexp" ]; then
  atentie "$(wc -l < "$W/afexp" | tr -d ' ') afirmatii au trecut de data de reverificare — de confruntat din nou cu sursa:"
  sed 's|^|             |' "$W/afexp"
fi
nper=$(awk -F'\t' '$8 != "-"' "$W/af" | wc -l | tr -d ' ')
[ -s "$W/afexp" ] || ok "$nper afirmatii cu termen de reverificare, niciunul depasit"

# detectorul de certitudine: textul public NEMARCAT care suna a dovada
cat > "$W/cert.awk" <<'AWK'
# Ruleaza cu LC_ALL=C: tolower atinge doar literele ASCII, identic pe orice
# implementare; literele cu diacritice se compara exact, octet cu octet.
# Potrivire pe cuvinte intregi: inainte si dupa tipar nu sta o litera
# ("overbeviser" nu e "beviser").  Octetii peste ~ (diacriticele) conteaza ca
# litere; cratima e granita, deci "s-a dovedit" si "a demonstrat-o" se prind.
function litera(c) { return c ~ /[a-z0-9]/ || c > "~" }
function cuvant(t, x,   poz, i, st) {
  poz = 1
  while ((i = index(substr(t, poz), x)) > 0) {
    st = poz + i - 1
    if (!(st > 1 && litera(substr(t, st - 1, 1))) && !litera(substr(t, st + length(x), 1))) return st
    poz = st + 1
  }
  return 0
}
BEGIN {
  while ((getline l < TF) > 0) { np++; p[np] = l; pl[np] = tolower(l) }
  # din pas55, un fragment acceptat poate fi legat de fisierul unde a fost citit:
  #   cale/fisier.html TAB fragment     (fara TAB: acceptat pe tot site-ul, ca pana acum)
  while ((getline l < OKF) > 0) { nk++; t = index(l, "\t"); if (t > 0) { kf[nk] = substr(l, 1, t - 1); k[nk] = substr(l, t + 1) } else { kf[nk] = ""; k[nk] = l } }
  M = "<span data-afirmatie=\""
}
{
  s = $0
  # afirmatiile marcate sunt deja in registru: se scot din text
  while ((i = index(s, M)) > 0) {
    r = substr(s, i); j = index(r, "</span>")
    if (j == 0) break
    s = substr(s, 1, i - 1) " " substr(r, j + 7)
  }
  gsub(/<[^>]*>/, " ", s); gsub(/[ \t\r]+/, " ", s)
  # fragmentele citite si acceptate
  for (q = 1; q <= nk; q++) { if (kf[q] != "" && kf[q] != R) continue; while ((i = index(s, k[q])) > 0) s = substr(s, 1, i - 1) " " substr(s, i + length(k[q])) }
  ls = tolower(s); gasit = ""; prim = 0
  for (q = 1; q <= np; q++) if ((i = cuvant(ls, pl[q])) > 0) {
    gasit = gasit (gasit == "" ? "" : ", ") p[q]
    if (prim == 0) prim = i
  }
  if (gasit == "") next
  a = prim - 50; if (a < 1) a = 1
  f = substr(s, a, 130)
  if (a > 1) sub(/^[^ ]* /, "", f)
  if (a + 130 <= length(s)) sub(/ [^ ]*$/, "", f)
  sub(/^ +/, "", f); sub(/ +$/, "", f)
  print R ":" FNR "\t" gasit "\t" f
}
AWK
if [ ! -f "$CERT" ]; then
  atentie "lipseste scripts/certitudini.txt — detectorul de certitudine nu ruleaza"
else
  grep -v '^#' "$CERT" | grep -v '^[[:space:]]*$' > "$W/cert"
  : > "$W/certok"
  [ -f "$CERT_OK" ] && grep -v '^#' "$CERT_OK" | grep -v '^[[:space:]]*$' > "$W/certok"
  : > "$W/certhit"
  while read -r f; do
    LC_ALL=C awk -v R="${f#"$RADACINA"/}" -v TF="$W/cert" -v OKF="$W/certok" -f "$W/cert.awk" "$f" >> "$W/certhit"
  done < "$W/pub13"
  if [ -s "$W/certhit" ]; then
    atentie "$(wc -l < "$W/certhit" | tr -d ' ') locuri cu cuvinte de certitudine in text nemarcat — de citit:"
    awk -F'\t' '{print "             " $1 "  [" $2 "]"; print "               ... " $3 " ..."}' "$W/certhit"
  else
    ok "niciun cuvant de certitudine in textul nemarcat ($(wc -l < "$W/cert" | tr -d ' ') tipare)"
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 14 "Citatele biblice == textul editiilor declarate (1688 RO, 1930 NO)"
# ════════════════════════════════════════════════════════════════════
# Fiecare <blockquote class="verse"> (si "hero-verse") din documente se confrunta
# cu editia declarata a limbii lui: RO — Biblia de la Bucuresti (1688),
# NO — Bibelen 1930 (Det Norske Bibelselskap).  Textele stau DOAR local,
# langa clone, in afara oricarui repo:
#     RADACINA/biblii/b1688.txt          RADACINA/biblii/Norsk-1930.json
# (alta cale: variabila NORGEDAN_BIBLII).
# Lipsa unui text NU mai trece in tacere (pas53):
#   push   — text lipsa sau cu alta amprenta = PROBLEMA; ocolire doar constienta,
#            vizibila in raport:  NORGEDAN_FARA_BIBLII=1 git push
#   manual — ATENTIE (esti in mijlocul lucrului)
#   ci     — NO se confrunta (verifica.yml aduce Bibelen 1930, commit fixat);
#            RO 1688 sta doar local, deci in CI se sare, declarat.
# Santinela: un text prezent din care nu iese niciun citat confruntat = PROBLEMA
# (extragerea s-a stricat; pe acest site sunt sute de citate).
# Confruntarea: aceleasi cuvinte, in aceeasi ordine; ghilimelele, apostroful,
# punctuatia si majusculele nu decid.  Taieturile marcate cu „…” sunt permise:
# fiecare bucata trebuie sa existe in verset, in ordine.
# Nu acopera (inca): citatele din proza, intre ghilimele, cu trimitere in paranteza.

BIBLII="${NORGEDAN_BIBLII:-$RADACINA/biblii}"
B1688="$BIBLII/b1688.txt"; B1930="$BIBLII/Norsk-1930.json"
# amprentele textelor confruntate (cksum): alt fisier = alte rezultate
CK1688="4063011430 5536761"; CK1930="428768866 8024090"

# textul de referinta lipsa sau schimbat: cat de grav, dupa mod
lipsa_text() {
  case "$MOD" in
    push|ci)
      if [ "$MOD" = push ] && [ "${NORGEDAN_FARA_BIBLII:-}" = 1 ]; then
        atentie "$1 — OCOLIRE CONSTIENTA (NORGEDAN_FARA_BIBLII=1): aceste citate nu sunt confruntate"
      else
        problema "$1 — citatele nu pot fi confruntate (ocolire doar constienta: NORGEDAN_FARA_BIBLII=1 git push)"
      fi ;;
    *) atentie "$1 — citatele nu sunt confruntate" ;;
  esac
}
ARE_RO=0; ARE_NO=0
if [ "$MOD" = ci ]; then
  echo "  (RO 1688 sarit in CI — textul sta doar local; NO 1930 se confrunta)"
elif [ -f "$B1688" ]; then ARE_RO=1
else lipsa_text "lipseste $B1688 (RO, Biblia 1688)"; fi
if [ -f "$B1930" ]; then ARE_NO=1
elif [ "$MOD" = ci ]; then problema "lipseste $B1930 in CI — pasul care il aduce din verifica.yml a esuat"
else lipsa_text "lipseste $B1930 (NO, Bibelen 1930)"; fi
if [ "$ARE_RO" = 1 ] && [ "$(cksum < "$B1688" | awk '{print $1, $2}')" != "$CK1688" ]; then
  lipsa_text "b1688.txt difera de textul cu care s-a lucrat (cksum)"; ARE_RO=0
fi
if [ "$ARE_NO" = 1 ] && [ "$(cksum < "$B1930" | awk '{print $1, $2}')" != "$CK1930" ]; then
  lipsa_text "Norsk-1930.json difera de textul cu care s-a lucrat (cksum)"; ARE_NO=0
fi
if [ "$ARE_RO" = 1 ] || [ "$ARE_NO" = 1 ]; then
  cat > "$W/idx1688.awk" <<'AWK'
# idx1688.awk — indexul Bibliei de la Bucuresti (1688): iesire  COD TAB cap TAB vers TAB text
BEGIN {
  n = split("FAC IES LEV NUM DEU IOS JDC RUT 1IMP 2IMP 3IMP 4IMP 1PAR 2PAR EZD NEE EST IOV " \
            "PAR ECL CANT ISA IER PLA IEZ DAN OSE IOI AMO AVD ION MIH NAU AVV SOF AGG ZAH MAL " \
            "TOV IUT VAR 3EZD INT SIR 1MAC 2MAC 3MAC 4MAC " \
            "MAT MAR LUC IOA FAP ROM 1COR 2COR GAL EFE FLP COL 1TES 2TES 1TIM 2TIM TIT FLM EVR " \
            "IAC 1PET 2PET 1IOA 2IOA 3IOA IUD APO", C, " ")
  k = 0; b = ""; cap = 0; v = 0
}
{ sub(/^[\f\r]+/, ""); sub(/\r$/, "") }
# trimiteri marginale lipite la sfarsitul versetului: "... zideaște. Fapt. Ap. 15, 20."
#   "... făcut. A 2 Leage 5, 14."   "... Enos. 5, 6."   "... 1, 26; 9, 6; Col. 3, 10."
# Se scot cuvant cu cuvant, de la coada: numere ("15," "20." "3-5;"), abrevieri scurte
# cu punct ("Fapt." "Ap." "Col.") si "A", "Leage".  Doar daca coada are o pereche "N, N".
function fara_trimiteri(t,   n, w, i, j, x) {
  if (t !~ /[0-9]+[,.] [0-9]+[-0-9,;.]*$/) return t
  n = split(t, w, " ")
  for (i = n; i > 0; i--) {
    x = w[i]
    if (x ~ /^[0-9]+(-[0-9]+)?[,;.]?$/) continue
    if (x == "A" || x == "Leage" || x == "Leage," ) continue
    if (x ~ /\.$/ && length(x) <= 9 && (x ~ /^[A-Z]/ || x ~ /^(Ă|Â|Î|Ș|Ț)/)) continue
    # nume intreg de carte ("Luca", "Neemia", "Sirah") urmat de un numar
    if (i < n && w[i + 1] ~ /^[0-9]/ && length(x) <= 9 && x ~ /^([A-Z]|Ă|Â|Î|Ș|Ț)[a-zăâîșț]*$/) continue
    break
  }
  if (i == n) return t
  x = ""; for (j = 1; j <= i; j++) x = x (j > 1 ? " " : "") w[j]
  return x
}
# o cheie apare o singura data: prima aparitie e versetul cartii (adaosurile vin dupa)
function flush(   key) {
  t = fara_trimiteri(t)
  key = b SUBSEP cap SUBSEP v; if (b != "" && v > 0 && !(key in vazut)) { vazut[key] = 1; print b "\t" cap "\t" v "\t" t }; v = 0; t = "" }
/^CAP 1$/ { flush(); k++; b = C[k]; cap = 1; next }
/^CAP [0-9]+$/ { flush(); cap = $2 + 0; next }
/^(CATHISMA [0-9]+\. )?PSALMUL [0-9]+$/ { flush(); b = "PSA"; cap = $NF + 0; next }
# dupa Apocalipsa urmeaza tabelele liturgice: indexul se opreste
b == "APO" && /^APOSTOLUL / { flush(); b = ""; stop = 1 }
stop { next }
# trimiteri marginale:  "Ioan 1, 1, 2; Evr. 1, 10."  "1 Paral. 2, 5."
/^([1-4] )?[A-ZĂÂÎȘȚ][^ ]* [0-9]+, [0-9]/ && /\.$/ { next }
{
  l = $0
  if (match(l, /^[0-9]+\.(\[[0-9]+\.[^]]*\])? */)) {
    flush(); num = substr(l, 1, RLENGTH); sub(/\..*/, "", num); v = num + 0
    t = substr(l, RLENGTH + 1); next
  }
  if (v > 0 && l != "") t = t " " l
}
END { flush(); if (k != 75) print "EROARE\t" k " carti, trebuie 75" > "/dev/stderr" }
AWK
  cat > "$W/idx1930.awk" <<'AWK'
# idx1930.awk — indexul Bibelen 1930 (JSON scrollmapper): iesire  COD TAB cap TAB vers TAB text
BEGIN {
  n = split("Genesis:FAC Exodus:IES Leviticus:LEV Numbers:NUM Deuteronomy:DEU Joshua:IOS Judges:JDC Ruth:RUT " \
    "I Samuel:1IMP II Samuel:2IMP I Kings:3IMP II Kings:4IMP I Chronicles:1PAR II Chronicles:2PAR Ezra:EZD " \
    "Nehemiah:NEE Esther:EST Job:IOV Psalms:PSA Proverbs:PAR Ecclesiastes:ECL Song of Solomon:CANT Isaiah:ISA " \
    "Jeremiah:IER Lamentations:PLA Ezekiel:IEZ Daniel:DAN Hosea:OSE Joel:IOI Amos:AMO Obadiah:AVD Jonah:ION " \
    "Micah:MIH Nahum:NAU Habakkuk:AVV Zephaniah:SOF Haggai:AGG Zechariah:ZAH Malachi:MAL Matthew:MAT Mark:MAR " \
    "Luke:LUC John:IOA Acts:FAP Romans:ROM I Corinthians:1COR II Corinthians:2COR Galatians:GAL Ephesians:EFE " \
    "Philippians:FLP Colossians:COL I Thessalonians:1TES II Thessalonians:2TES I Timothy:1TIM II Timothy:2TIM " \
    "Titus:TIT Philemon:FLM Hebrews:EVR James:IAC I Peter:1PET II Peter:2PET I John:1IOA II John:2IOA " \
    "III John:3IOA Jude:IUD Revelation of John:APO", P, " ")
  # numele cu spatii au fost taiate de split: le refacem
  s = ""; for (i = 1; i <= n; i++) { s = s (s == "" ? "" : " ") P[i]; if (s ~ /:/) { k = s; sub(/:.*/, "", k); v = s; sub(/^[^:]*:/, "", v); M[k] = v; s = "" } }
}
/"name": "/  { x = $0; sub(/^[^"]*"name": "/, "", x); sub(/",?[ \t]*$/, "", x); b = (x in M) ? M[x] : "?" x; next }
/"chapter": / { x = $0; gsub(/[^0-9]/, "", x); cap = x + 0; next }
/"verse": /   { x = $0; gsub(/[^0-9]/, "", x); v = x + 0; next }
/"text": "/   { x = $0; sub(/^[^"]*"text": "/, "", x); sub(/"[ \t]*,?[ \t]*$/, "", x); gsub(/\\"/, "\"", x); gsub(/\\\\/, "\\", x)
  # erata textului digital (scrollmapper, la fel pe biblehub): cuvinte dublate la digitizare
  if (b == "2TIM" && cap == 3 && v == 16) sub(/av Gud av Gud/, "av Gud", x)
  print b "\t" cap "\t" v "\t" x }
AWK
  cat > "$W/citate.awk" <<'AWK'
# citate.awk — confrunta blocurile <blockquote class="verse"> cu textul de referinta.
# Variabile: IDX (indexul: COD TAB cap TAB vers TAB text), LIMBA (ro|no), R (calea afisata).
# Iesire, cate o linie pe bloc:  STARE TAB R TAB referinta TAB detaliu
#   STARE = OK | GRESIT | NEGASIT | SARIT | NECUNOSCUT
function lower(s) {
  s = tolower(s)
  gsub(/Ă/, "ă", s); gsub(/Â/, "â", s); gsub(/Î/, "î", s); gsub(/Ș/, "ș", s); gsub(/Ț/, "ț", s)
  gsub(/Ş/, "ș", s); gsub(/Ţ/, "ț", s); gsub(/ş/, "ș", s); gsub(/ţ/, "ț", s)
  gsub(/Å/, "å", s); gsub(/Æ/, "æ", s); gsub(/Ø/, "ø", s); gsub(/É/, "é", s)
  return s
}
# blocul e citat biblic daca atributul class contine cuvantul "verse" sau
# "hero-verse" (pas54): <blockquote class="verse x"> sau class='verse' nu mai
# scapa nevazute, cum scapau cand se cauta sirul exact class="verse".
function e_verse(tag,   v, n, w, i) {
  if (match(tag, /class[ \t\r\n]*=[ \t\r\n]*"[^"]*"/) || match(tag, /class[ \t\r\n]*=[ \t\r\n]*'[^']*'/)) {
    v = substr(tag, RSTART, RLENGTH); sub(/^[^"']*["']/, "", v); sub(/["']$/, "", v)
    n = split(v, w, /[ \t\r\n]+/)
    for (i = 1; i <= n; i++) if (w[i] == "verse" || w[i] == "hero-verse") return 1
  }
  return 0
}
function norm(s) {
  gsub(/<[^>]*>/, " ", s)
  gsub(/&nbsp;/, " ", s); gsub(/&amp;/, "\\&", s); gsub(/&quot;/, " ", s); gsub(/&#39;/, "'", s)
  gsub(/„|“|”|"|«|»|‹|›/, " ", s)
  gsub(/’|‘|`/, "'", s)
  gsub(/↡|↟/, " ", s); gsub(/\[[0-9]+\.[^]]*\]/, " ", s)
  gsub(/–|—/, " ", s)
  gsub(/[ \t\r\n]+/, " ", s)
  s = lower(s)
  # semnele de punctuatie nu decid: se scot, ca virgula din citat sa nu conteze fata de punct
  gsub(/[.,;:!?()]/, " ", s)
  gsub(/ +/, " ", s); sub(/^ /, "", s); sub(/ $/, "", s)
  return s
}
BEGIN {
  FS = "\t"
  while ((getline l < IDX) > 0) { split(l, a, "\t"); T[a[1] SUBSEP a[2] SUBSEP a[3]] = a[4]; ARE[a[1]] = 1 }
  n = split("Facerea:FAC|Geneza:FAC|Ieșirea:IES|Psalmul:PSA|Psalmii:PSA|Paremiile lui Solomon:PAR|Pildele lui Solomon:PAR|" \
    "Eclesiastul:ECL|Isaia:ISA|Ieremia:IER|Iezechiil:IEZ|Daniil:DAN|Înțelepciunea lui Solomon:INT|Iov:IOV|" \
    "Matei:MAT|Marcu:MAR|Luca:LUC|Ioan:IOA|Faptele Apostolilor:FAP|Romani:ROM|Efeseni:EFE|Evrei:EVR|" \
    "1 Ioan:1IOA|Apocalipsa:APO|1 Corinteni:1COR|2 Corinteni:2COR|Galateni:GAL|Filipeni:FLP|Coloseni:COL|Iacov:IAC|1 Petru:1PET|1 Timotei:1TIM|2 Timotei:2TIM|Isus Navi:IOS|Iisus Navi:IOS|Apocalipsis:APO|A Doua Lege:DEU|Numerii:NUM|Preoția:LEV|" \
    "1 Mosebok:FAC|2 Mosebok:IES|Salme:PSA|Salmene:PSA|Ordspråkene:PAR|Salomos Ordsprog:PAR|Forkynneren:ECL|" \
    "Jesaja:ISA|Jeremia:IER|Esekiel:IEZ|Daniel:DAN|Visdommens bok:INT|Job:IOV|Matteus:MAT|Markus:MAR|" \
    "Lukas:LUC|Johannes:IOA|Apostlenes gjerninger:FAP|Romerne:ROM|Efeserne:EFE|Hebreerne:EVR|" \
    "1 Johannes:1IOA|Åpenbaringen:APO|1 Korinterbrev:1COR|2 Korinterbrev:2COR|Galaterne:GAL|Filipperne:FLP|Kolosserne:COL|Jakob:IAC|1 Peter:1PET|1 Timoteus:1TIM|2 Timoteus:2TIM|Josva:IOS|3 Mosebok:LEV|4 Mosebok:NUM|5 Mosebok:DEU", c, "|")
  for (i = 1; i <= n; i++) { k = c[i]; sub(/:[^:]*$/, "", k); v = c[i]; sub(/^.*:/, "", v); CARTE[k] = v }
  RS = "\001"
}
{
  s = $0
  # fiecare <blockquote ...>; e citat biblic daca clasa contine verse / hero-verse
  while ((i = index(s, "<blockquote")) > 0) {
    s = substr(s, i + 11); e = index(s, ">"); if (e == 0) break
    tag = substr(s, 1, e - 1); s = substr(s, e + 1)
    if (tag !~ /^([ \t\r\n]|$)/ || !e_verse(tag)) continue
    j = index(s, "</blockquote>"); if (j == 0) break
    bloc = substr(s, 1, j - 1); s = substr(s, j + 13)
    ci = index(bloc, "<cite>"); cj = index(bloc, "</cite>")
    if (ci > 0 && cj > 0) { cite = substr(bloc, ci + 6, cj - ci - 6); citat = substr(bloc, 1, ci - 1) }
    else {
      # fara <cite>: trimiterea sta dupa ghilimelele de inchidere (Doc VI)
      u = 0; t2 = bloc
      while (match(t2, /"|”|»|“/)) { u += RSTART + RLENGTH - 1; t2 = substr(t2, RSTART + RLENGTH) }
      if (u > 0) { citat = substr(bloc, 1, u); cite = substr(bloc, u + 1) }
      else {
        # fara ghilimele: trimiterea e ultimul rand nevid al blocului
        t2 = bloc; sub(/[ \t\r\n]+$/, "", t2); u = 0
        for (q = length(t2); q > 0; q--) if (substr(t2, q, 1) == "\n") { u = q; break }
        # un bloc de citat biblic fara nicio trimitere nu poate fi confruntat (pas54: PROBLEMA)
        if (u == 0) { print "NECUNOSCUT\t" R "\t-\tbloc de citat fara trimitere"; continue }
        citat = substr(t2, 1, u); cite = substr(t2, u + 1)
      }
    }
    gsub(/<[^>]*>/, "", cite); gsub(/[ \t\r\n]+/, " ", cite); sub(/^ /, "", cite); sub(/ $/, "", cite)
    if (cite == "") { print "NECUNOSCUT\t" R "\t-\tbloc de citat fara trimitere"; continue }
    # referinta: "Carte cap:vers[-vers][,vers]" la inceputul lui <cite>
    if (!match(cite, /^([1-5] )?[^0-9]+ [0-9]+:[0-9][-0-9,]*/)) {
      # incepe cu numele unei carti biblice, dar fara forma cap:vers ("1 Mosebok 3.22",
      # "Matei 5") = trimitere stricata, PROBLEMA (pas54).  Alti autori raman sariti.
      stricat = 0
      for (k in CARTE) if (index(cite, k " ") == 1 || cite == k) { stricat = 1; break }
      if (stricat) print "NECUNOSCUT\t" R "\t" cite "\ttrimitere biblica fara forma carte cap:vers"
      else print "SARIT\t" R "\t" cite "\tnu e trimitere biblica"
      continue
    }
    ref = substr(cite, 1, RLENGTH); rest = substr(cite, RLENGTH + 1)
    if (rest ~ /ebraic|hebraisk/) { print "SARIT\t" R "\t" ref "\ttraducere din ebraica, declarata in <cite>"; continue }
    k = ref; sub(/ [0-9]+:[-0-9,]*$/, "", k)
    if (index(k, ",")) { print "SARIT\t" R "\t" ref "\tautor si opera, nu carte biblica"; continue }
    if (!(k in CARTE)) { print "NECUNOSCUT\t" R "\t" ref "\tcartea \"" k "\" nu e in tabelul de nume"; continue }
    cod = CARTE[k]
    if (!(cod in ARE)) { print "SARIT\t" R "\t" ref "\tcartea nu exista in editia de referinta"; continue }
    cv = substr(ref, length(k) + 2); cap = cv; sub(/:.*/, "", cap); lv = cv; sub(/^[^:]*:/, "", lv)
    txt = ""; lipsa = ""
    m = split(lv, parti, ",")
    for (q = 1; q <= m; q++) {
      va = parti[q]; vb = va
      if (index(va, "-")) { vb = va; sub(/^[^-]*-/, "", vb); sub(/-.*/, "", va) }
      for (vv = va + 0; vv <= vb + 0; vv++) {
        key = cod SUBSEP (cap + 0) SUBSEP vv
        if (key in T) txt = txt " " T[key]; else lipsa = lipsa " " vv
      }
    }
    if (lipsa != "") { print "NEGASIT\t" R "\t" ref "\tversetul" lipsa " nu e in index"; continue }
    nt = norm(txt)
    # citatul poate avea taieturi: "…", "[…]", "..." — fiecare bucata, in ordine
    gsub(/\[…\]|\[\.\.\.\]|…|\.\.\./, "\002", citat)
    # un fragment de 1-3 cuvinte se gaseste in aproape orice verset: nu confrunta nimic
    # (pas54).  Pe site, cel mai scurt citat are 5 cuvinte.
    x = citat; gsub(/\002/, " ", x); x = norm(x)
    nw = (x == "") ? 0 : split(x, ww, " ")
    if (nw < 4) { print "GRESIT\t" R "\t" ref "\tcitat prea scurt (" nw " cuvinte, minim 4) — nu poate fi confruntat"; continue }
    nb = split(citat, buc, "\002"); poz = 1; bun = 1; rau = ""
    for (q = 1; q <= nb; q++) {
      x = norm(buc[q]); if (x == "") continue
      r = index(substr(nt, poz), x)
      if (r == 0) { bun = 0; rau = x; break }
      poz = poz + r - 1 + length(x)
    }
    if (bun) print "OK\t" R "\t" ref "\t-"
    else print "GRESIT\t" R "\t" ref "\tpe site: \"" substr(rau, 1, 70) "\" | editia: \"" substr(nt, 1, 70) "\""
  }
}
AWK
  : > "$W/i1688"; : > "$W/i1930"
  if [ "$ARE_RO" = 1 ]; then
    LC_ALL=C awk -f "$W/idx1688.awk" "$B1688" > "$W/i1688" 2> "$W/i1688.err"
    [ -s "$W/i1688.err" ] && problema "indexul 1688: $(cat "$W/i1688.err")"
  fi
  [ "$ARE_NO" = 1 ] && LC_ALL=C awk -f "$W/idx1930.awk" "$B1930" > "$W/i1930"
  : > "$W/cit"
  while IFS="$TAB" read -r repo cale limba id col tit; do
    f="$RADACINA/$repo/$cale"; [ -f "$f" ] || continue
    if [ "$limba" = ro ]; then [ "$ARE_RO" = 1 ] || continue; ix="$W/i1688"
    else [ "$ARE_NO" = 1 ] || continue; ix="$W/i1930"; fi
    LC_ALL=C awk -v IDX="$ix" -v R="$repo/$cale" -f "$W/citate.awk" "$f" | sed "s/\$/$TAB$limba/" >> "$W/cit"
  done < "$W/docs"
  greseli=0
  awk -F'\t' '$1=="GRESIT" || $1=="NEGASIT" || $1=="NECUNOSCUT" {print $2 " — " $3 ": " $4}' "$W/cit" > "$W/citp"
  while read -r l; do problema "$l"; greseli=1; done < "$W/citp"
  # limba vine din manifest (ultima coloana), nu din numele fisierului
  nro=$(awk -F'\t' '$1=="OK" && $NF=="ro"' "$W/cit" | wc -l | tr -d ' ')
  nno=$(awk -F'\t' '$1=="OK" && $NF!="ro"' "$W/cit" | wc -l | tr -d ' ')
  # santinela: un text prezent, zero citate confruntate = extragerea s-a stricat
  [ "$ARE_RO" = 1 ] && [ "$nro" -eq 0 ] && { problema "niciun citat RO confruntat, desi b1688.txt e prezent — citirea blocurilor sau indexul s-a stricat"; greseli=1; }
  [ "$ARE_NO" = 1 ] && [ "$nno" -eq 0 ] && { problema "niciun citat NO confruntat, desi Norsk-1930.json e prezent — citirea blocurilor sau indexul s-a stricat"; greseli=1; }
  if [ "$greseli" -eq 0 ]; then
    if [ "$ARE_RO" = 1 ] && [ "$ARE_NO" = 1 ]; then ok "$((nro + nno)) citate biblice identice cu editia declarata (RO 1688: $nro, NO 1930: $nno)"
    elif [ "$ARE_NO" = 1 ]; then ok "$nno citate NO identice cu Bibelen 1930 (RO neconfruntat aici)"
    else ok "$nro citate RO identice cu Biblia 1688 (NO neconfruntat aici)"; fi
  fi
  nabs=$(awk -F'\t' '$1=="SARIT" && $4 ~ /nu exista in editia/' "$W/cit" | wc -l | tr -d ' ')
  [ "$nabs" -gt 0 ] && atentie "$nabs citate din carti absente din editia de referinta (de ex. Intelepciunea lui Solomon in Bibelen 1930) — neconfruntate"
fi

# ════════════════════════════════════════════════════════════════════
titlu 15 "Paritatea RO-NO: aceeasi structura in ambele limbi"
# ════════════════════════════════════════════════════════════════════
# O pereche RO+NO e acelasi document: aceleasi capitole (<h2>), subcapitole
# (<h3>), citate biblice (blocuri verse) si o lungime asemanatoare (textul NO
# are de obicei 70-90% din cuvintele RO).  O diferenta nu e neaparat o greseala
# — poate fi o adaptare constienta — dar asa au ramas nevazute capitole lipsa
# si erori de traducere.  Toate semnalarile sunt ATENTIE.
#   scripts/paritate-ok.txt   diferente citite si acceptate:  id TAB masura TAB RO/NO
#   (valoarea exacta: daca diferenta se schimba, semnalarea revine)
PARIT_OK="$SCRIPT_DIR/paritate-ok.txt"
: > "$W/parok"; [ -f "$PARIT_OK" ] && grep -v '^#' "$PARIT_OK" | grep -v '^[[:space:]]*$' > "$W/parok"
cat > "$W/par.awk" <<'AWK'
BEGIN { FS = "\t" }
$1 == "h2" { h2++ } $1 == "h3" { h3++ }
# aceeasi regula ca la [14]: clasa contine cuvantul verse / hero-verse
$1 == "blockquote" { for (i = 2; i < NF; i += 2) if ($i == "class") { n = split($(i+1), cl, " "); for (k = 1; k <= n; k++) if (cl[k] == "verse" || cl[k] == "hero-verse") { v++; break } } }
END { print h2 + 0, h3 + 0, v + 0 }
AWK
: > "$W/par"
while IFS="$TAB" read -r id col repo cro cno tro tno; do
  fro="$RADACINA/$repo/$cro"; fno="$RADACINA/$repo/$cno"
  [ -f "$fro" ] && [ -f "$fno" ] || continue
  set -- $(awk -f "$W/par.awk" "$(tagsf "$fro")") $(awk -f "$W/par.awk" "$(tagsf "$fno")")
  # santinela: un document fara niciun <h2> citit = structura sau citirea s-a stricat
  [ "$1" -eq 0 ] && problema "$id: $repo/$cro nu are niciun capitol (<h2>) citit"
  [ "$4" -eq 0 ] && problema "$id: $repo/$cno nu are niciun capitol (<h2>) citit"
  wro=$(cuvinte "$fro"); wno=$(cuvinte "$fno")
  for m in "capitole $1/$4" "subcapitole $2/$5" "citate $3/$6"; do
    n=${m%% *}; v=${m#* }
    [ "${v%/*}" = "${v#*/}" ] && continue
    printf '%s\t%s\t%s\n' "$id" "$n" "$v" >> "$W/par"
  done
  if [ "$wro" -gt 0 ] && [ $((wno * 100 / wro)) -lt 70 ]; then
    printf '%s\t%s\t%s\n' "$id" "lungime" "$wro/$wno ($((wno * 100 / wro))%)" >> "$W/par"
  fi
done < "$W/m"
# lista acceptata se citeste in BEGIN: cu NR==FNR, o lista goala ar inghiti tot
awk -F'\t' -v OKF="$W/parok" 'BEGIN { while ((getline l < OKF) > 0) ok[l] = 1 } !(($1 "\t" $2 "\t" $3) in ok)' "$W/par" > "$W/parx"
if [ -s "$W/parx" ]; then
  atentie "$(cut -f1 "$W/parx" | sort -u | wc -l | tr -d ' ') perechi RO-NO cu structura diferita — de citit (RO/NO):"
  awk -F'\t' '{ d[$1] = d[$1] (d[$1] == "" ? "" : ", ") $2 " " $3 } END { for (k in d) print "             " k ": " d[k] }' "$W/parx" | sort
else
  ok "toate perechile RO-NO au aceeasi structura (sau diferenta e acceptata in paritate-ok.txt)"
fi

# ════════════════════════════════════════════════════════════════════
titlu 16 "Pilonii: temelia declarata, cu limita ei, ancorata in pagini"
# ════════════════════════════════════════════════════════════════════
# scripts/piloni.tsv tine afirmatiile pe care se sprijina documentele, fiecare
# cu eticheta reala si cu ce NU dovedeste.  Un pilon ancorat trebuie sa-si
# gaseasca fragmentul exact in pagina RO si in perechea NO: daca textul e
# schimbat sau sters, temelia s-a mutat fara sa se vada — PROBLEMA.
PILONI="$SCRIPT_DIR/piloni.tsv"
if [ ! -f "$PILONI" ]; then
  problema "lipseste scripts/piloni.tsv"
else
  grep -v '^#' "$PILONI" | grep -v '^[[:space:]]*$' > "$W/pil"
  awk -F'\t' '
    NF != 9 { print "rand " NR ": " NF " coloane in loc de 9"; next }
    $1 !~ /^[a-z0-9-]+$/ { print "id gresit: " $1 }
    $2 !~ /^(FAPT|ESTIMARE|INTERPRETARE|CREDINTA)$/ { print $1 ": eticheta necunoscuta " $2 }
    { for (i = 1; i <= 9; i++) if ($i ~ /^[[:space:]]*$/) print $1 ": coloana " i " goala (se scrie \"-\")" }
    $5 == "-" { print $1 ": lipseste limita — ce NU dovedeste pilonul" }
    $4 == "-" && $2 != "CREDINTA" { print $1 ": lipseste sursa" }
    ($6 == "-") != ($8 == "-") { print $1 ": ancorat doar intr-o limba (RO si NO merg impreuna)" }
    ($6 == "-") != ($7 == "-") || ($8 == "-") != ($9 == "-") { print $1 ": fisier fara ancora sau ancora fara fisier" }
    seen[$1]++ == 1 { print "id dublat: " $1 }
  ' "$W/pil" > "$W/pilerr"
  na=0
  while IFS="$TAB" read -r id et pil src lim fro aro fno ano; do
    for p in "$fro$TAB$aro" "$fno$TAB$ano"; do
      f=${p%%"$TAB"*}; a=${p#*"$TAB"}
      [ "$f" = "-" ] && continue
      if [ ! -f "$RADACINA/$f" ]; then echo "$id: nu exista $f" >> "$W/pilerr"
      elif grep -qF -- "$a" "$RADACINA/$f"; then na=$((na + 1))
      else echo "$id: ancora nu mai e in $f — „$a”" >> "$W/pilerr"; fi
    done
  done < "$W/pil"
  if [ -s "$W/pilerr" ]; then
    while IFS= read -r l; do problema "$l"; done < "$W/pilerr"
  else
    np=$(wc -l < "$W/pil" | tr -d ' ')
    ok "$np piloni, toti cu eticheta, sursa si limita; $na ancore gasite in pagini, RO si NO"
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 17 "Vocea: fiecare document se poate asculta"
# ════════════════════════════════════════════════════════════════════
# asculta.js sta o singura data, in radacina hub-ului (norgedan.github.io/),
# si e incarcat de fiecare document cu <script src="/asculta.js" defer>.
# Cale absoluta: toate repo-urile se publica sub acelasi domeniu.
VOCE="$RADACINA/norgedan.github.io/asculta.js"
if [ ! -f "$VOCE" ]; then
  problema "lipseste norgedan.github.io/asculta.js — niciun document nu se poate asculta"
else
  : > "$W/voce"
  while IFS="$TAB" read -r id col repo cro cno tro tno; do
    for f in "$repo/$cro" "$repo/$cno"; do
      [ -f "$RADACINA/$f" ] || continue
      grep -qF '<script src="/asculta.js" defer></script>' "$RADACINA/$f" || echo "$f" >> "$W/voce"
    done
  done < "$W/m"
  if [ -s "$W/voce" ]; then
    while IFS= read -r f; do problema "$f nu incarca /asculta.js — documentul nu se poate asculta"; done < "$W/voce"
  else
    ok "toate cele $(($(wc -l < "$W/m") * 2)) fisiere-document incarca vocea (asculta.js, RO si NO)"
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 18 "Capitolele verificate la sursa: textul de dupa verificare"
# ════════════════════════════════════════════════════════════════════
# Din pas63.  Regula de lucru (21 oct 2026): la fiecare capitol, intai cifrele si
# faptele din RO reverificate la sursa, apoi traducerea.  Masina nu poate judeca
# daca un capitol e adevarat si nici in ce ordine s-a lucrat; poate face vizibil
# ce s-a schimbat DUPA verificare si ce n-a fost verificat niciodata.
#
#   scripts/capitole-verificate.tsv — un rand = un capitol verificat la sursa:
#     id  poz  titlu-RO  pas  data  amprenta-RO  amprenta-NO  nota      (TAB)
#   poz    = al catelea <h2> din pagina, numarat de sus (introducerea inclusa);
#            perechea NO = acelasi <h2> ca pozitie
#   titlu  = titlul RO al capitolului, asa cum e in pagina: daca la pozitia
#            aceea apare alt titlu, capitolele s-au mutat — PROBLEMA
#   capitolul N = de la al N-lea <h2> pana la urmatorul; ultimul, pana la primul
#            <footer, </main> sau </body>; fara comentarii, <style>, <script>,
#            fara tag-uri, spatiile unificate; amprenta = cksum, ca in amprente.tsv
# Blocheaza: rand stricat, capitol inexistent, titlu mutat, amprenta lipsa,
#            text RO sau NO schimbat dupa verificare.
# Semnaleaza: capitolele neverificate inca (datoria), perechile cu numar diferit
#            de capitole (pozitiile pot sa nu corespunda).
# Dupa reverificarea la sursa a unui capitol schimbat: pas si data noi in rand,
#   apoi  sh verifica-site.sh --capitole  (rescrie titlul si amprentele),
#   apoi  git diff scripts/capitole-verificate.tsv  citit inainte de commit.
# Un capitol nou verificat: rand nou cu "-" la titlu si amprente, apoi --capitole.
CAPV="$SCRIPT_DIR/capitole-verificate.tsv"
cat > "$W/cap.awk" <<'AWK'
function curata(t) {
  gsub(/<[^>]*>/, " ", t); gsub(/&nbsp;/, " ", t); gsub(/\302\240/, " ", t)
  gsub(/[ \t\r\n]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
  return t
}
function scoate(s, a, b,   out, i, j) {
  out = ""
  while ((i = index(s, a)) > 0) {
    out = out substr(s, 1, i - 1); s = substr(s, i)
    j = index(s, b); if (j == 0) { s = ""; break }
    s = substr(s, j + length(b))
  }
  return out s
}
BEGIN { RS = "\001" }
{
  s = scoate($0, "<!--", "-->"); s = scoate(s, "<script", "</script>"); s = scoate(s, "<style", "</style>")
  n = 0
  while ((i = index(s, "<h2")) > 0) {
    s = substr(s, i + 3); n++
    j = index(s, "<h2"); if (j == 0) j = length(s) + 1
    c = substr(s, 1, j - 1)
    if (index(s, "<h2") == 0) {
      e = length(c) + 1
      split("<footer </main> </body>", z, " ")
      for (k = 1; k <= 3; k++) { p = index(c, z[k]); if (p > 0 && p < e) e = p }
      c = substr(c, 1, e - 1)
    }
    g = index(c, ">"); h = index(c, "</h2>")
    tit = (g > 0 && h > g) ? curata(substr(c, g + 1, h - g - 1)) : "?"
    print n "\t" tit "\t" curata("<h2" c)
  }
}
AWK
# capitolele masurate:  id TAB limba TAB poz TAB titlu TAB amprenta
: > "$W/capm"
while IFS="$TAB" read -r id col repo cro cno tro tno; do
  for p in "ro$TAB$repo/$cro" "no$TAB$repo/$cno"; do
    l=${p%%"$TAB"*}; f="$RADACINA/${p#*"$TAB"}"
    [ -f "$f" ] || continue
    LC_ALL=C awk -f "$W/cap.awk" "$f" | while IFS="$TAB" read -r n tit txt; do
      printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$l" "$n" "$tit" "$(printf '%s' "$txt" | cksum | awk '{print $1 "-" $2}')"
    done >> "$W/capm"
  done
done < "$W/m"
: > "$W/capv"; [ -f "$CAPV" ] && grep -v '^#' "$CAPV" | grep -v '^[[:space:]]*$' > "$W/capv"

if [ "$MOD" = capitole ]; then
  if [ ! -f "$CAPV" ]; then echo "  lipseste $CAPV"; exit 1; fi
  { grep '^#' "$CAPV"
    awk -F'\t' -v M="$W/capm" '
      BEGIN { OFS = "\t"; while ((getline l < M) > 0) { split(l, x, "\t"); k = x[1] "\t" x[3]
              if (x[2] == "ro") { t[k] = x[4]; ar[k] = x[5] } else an[k] = x[5] } }
      { k = $1 "\t" $2
        if ((k in t) && (k in an)) { $3 = t[k]; $6 = ar[k]; $7 = an[k] }
        print }' "$W/capv"
  } > "$W/capnou"
  cp "$W/capnou" "$CAPV"
  echo ""
  echo "  capitole-verificate.tsv rescris: $(wc -l < "$W/capv" | tr -d ' ') capitole.  Citeste diferenta inainte de commit:"
  echo "    git -C $HUB diff scripts/capitole-verificate.tsv"
  echo ""
  exit 0
fi

# santinela: documente in manifest, dar niciun capitol citit = extragerea s-a stricat
if [ ! -s "$W/capm" ]; then
  problema "niciun capitol citit din documente — extragerea capitolelor s-a stricat"
elif [ ! -f "$CAPV" ]; then
  problema "lipseste scripts/capitole-verificate.tsv"
else
  awk -F'\t' -v M="$W/capm" -v MF="$W/m" '
    BEGIN { while ((getline l < MF) > 0) { split(l, x, "\t"); doc[x[1]] = 1 }
            while ((getline l < M) > 0) { split(l, x, "\t"); k = x[1] "\t" x[3]
              if (x[2] == "ro") { t[k] = x[4]; ar[k] = x[5] } else an[k] = x[5] } }
    NF != 8 { print "rand " NR ": " NF " coloane in loc de 8"; next }
    { for (i = 1; i <= 8; i++) if ($i ~ /^[[:space:]]*$/) { print $1 " poz " $2 ": coloana " i " goala (se scrie \"-\")"; next } }
    !($1 in doc) { print $1 ": nu e in manifest"; next }
    $2 !~ /^[1-9][0-9]*$/ { print $1 ": pozitie gresita \"" $2 "\""; next }
    $4 !~ /^pas[0-9]+[a-z]?$/ { print $1 " poz " $2 ": pas gresit \"" $4 "\" (ex: pas63)" }
    $5 !~ /^20[0-9][0-9]-[01][0-9]-[0-3][0-9]$/ { print $1 " poz " $2 ": data gresita \"" $5 "\" (AAAA-LL-ZZ)" }
    seen[$1 "\t" $2]++ == 1 { print $1 " poz " $2 ": rand dublat" }
    { k = $1 "\t" $2
      if (!(k in t) || !(k in an)) { print $1 ": capitolul " $2 " nu exista (in RO sau in NO)"; next }
      if ($3 == "-" || $6 == "-" || $7 == "-") { print $1 " poz " $2 ": fara titlu sau amprenta — dupa verificarea la sursa: --capitole"; next }
      if ($3 != t[k]) { print $1 " poz " $2 ": la pozitia asta nu mai e „" $3 "”, ci „" t[k] "” — capitolele s-au mutat sau titlul s-a schimbat dupa verificarea din " $4; next }
      if ($6 != ar[k]) print $1 " poz " $2 " „" t[k] "”, RO: textul s-a schimbat dupa verificarea din " $4 " — reverifica la sursa, pas si data noi, apoi --capitole"
      if ($7 != an[k]) print $1 " poz " $2 " „" t[k] "”, NO: textul s-a schimbat dupa verificarea din " $4 " — reverifica la sursa, pas si data noi, apoi --capitole" }
  ' "$W/capv" > "$W/caperr"
  if [ -s "$W/caperr" ]; then
    while IFS= read -r l; do problema "$l"; done < "$W/caperr"
  else
    nv=$(wc -l < "$W/capv" | tr -d ' ')
    if [ "$nv" -eq 0 ]; then ok "registrul capitolelor verificate e gol"
    else ok "$nv capitole verificate la sursa, cu titlul la locul lui si textul RO si NO neschimbat de atunci"; fi
  fi
  # pozitiile pot sa nu corespunda cand RO si NO au numar diferit de capitole
  awk -F'\t' -v M="$W/capm" '
    BEGIN { while ((getline l < M) > 0) { split(l, x, "\t"); if (x[2] == "ro") r[x[1]]++; else o[x[1]]++ } }
    !s[$1]++ && r[$1] != o[$1] { print $1 ": " r[$1] " capitole in RO, " o[$1] " in NO — pozitiile verificate pot sa nu corespunda" }
  ' "$W/capv" | while IFS= read -r l; do atentie "$l"; done
  # datoria de verificare: vizibila la fiecare rulare, fara sa blocheze
  awk -F'\t' -v V="$W/capv" '
    BEGIN { while ((getline l < V) > 0) { split(l, x, "\t"); v[x[1] "\t" x[2]] = 1 } }
    $2 == "ro" { tot[$1]++; if (!(($1 "\t" $3) in v)) { nev[$1]++; N++ } else A++; if (!($1 in ord)) { ord[$1] = ++k; id[k] = $1 } }
    END { if (N == 0) exit
          printf "%d %d\n", N, N + A
          for (i = 1; i <= k; i++) { d = id[i]; if (nev[d] > 0) printf "             %s: %d din %d\n", d, nev[d], tot[d] } }
  ' "$W/capm" > "$W/capdat"
  if [ -s "$W/capdat" ]; then
    set -- $(head -1 "$W/capdat")
    atentie "$1 din $2 capitole fara verificare intreaga inregistrata (datoria; afirmatiile marcate sunt verificate separat, in [13]):"
    sed 1d "$W/capdat"
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 19 "Unde e riscul: cifre si superlative in capitolele neverificate"
# ════════════════════════════════════════════════════════════════════
# Din pas67.  Auditul pasilor 56-66: erorile gasite la verificare au fost, de
# fiecare data, intr-o cifra (invechita, rotunjita, atenuata) sau intr-un superlativ
# fara sursa („cea mai dura”, „a doua cea mai mica”, „singurul”).  Masina nu stie
# care cifra e gresita; stie unde sunt multe, in text inca neverificat.  De aici
# lista: capitolele RO neverificate, ordonate dupa cifre + 2 x superlative —
# unde se sapa intai.  Doar semnalare, nu blocaj.
#   cifra      = grup de cifre, fara anii singuri (1000-2099) si fara cap:vers
#   superlativ = tiparele din SUPERL (RO si NO), cautate in textul trecut la litere mici
SUPERL="cel mai |cea mai |cei mai |cele mai |fără precedent|singurul |singura |unicul |unica |record |den største|det største|de største|høyeste|laveste|eneste |uten sidestykke|rekord"
cat > "$W/risc.awk" <<'AWK'
BEGIN { FS = "\t"; nr = split(SP, sp, "|") }
{
  t = $5; c = 0; s = t
  while (match(s, /[0-9]+([.,][0-9]+)*/)) {
    tok = substr(s, RSTART, RLENGTH); pre = (RSTART > 1) ? substr(s, RSTART - 1, 1) : " "
    post = substr(s, RSTART + RLENGTH, 1); s = substr(s, RSTART + RLENGTH)
    if (pre == ":" || post == ":") continue
    if (tok ~ /^(1[0-9]|20)[0-9][0-9]$/) continue
    c++
  }
  sup = 0; low = tolower(t)
  for (i = 1; i <= nr; i++) { u = low; while ((k = index(u, sp[i])) > 0) { sup++; u = substr(u, k + length(sp[i])) } }
  print $1 "\t" $2 "\t" $3 "\t" c "\t" sup "\t" $4
}
AWK
: > "$W/riscin"
while IFS="$TAB" read -r id col repo cro cno tro tno; do
  for p in "ro$TAB$repo/$cro" "no$TAB$repo/$cno"; do
    l=${p%%"$TAB"*}; f="$RADACINA/${p#*"$TAB"}"
    [ -f "$f" ] || continue
    LC_ALL=C awk -f "$W/cap.awk" "$f" | awk -F'\t' -v id="$id" -v l="$l" 'BEGIN { OFS = "\t" } { print id, l, $1, $2, $3 }' >> "$W/riscin"
  done
done < "$W/m"
LC_ALL=C awk -v SP="$SUPERL" -f "$W/risc.awk" "$W/riscin" > "$W/risc"
if [ ! -s "$W/risc" ]; then
  problema "niciun capitol citit pentru masurarea riscului — extragerea s-a stricat"
else
  # doar capitolele RO neverificate (cele din capitole-verificate.tsv au fost citite la sursa)
  awk -F'\t' -v V="$W/capv" '
    BEGIN { while ((getline l < V) > 0) { split(l, x, "\t"); v[x[1] "\t" x[2]] = 1 } }
    $2 == "ro" && !(($1 "\t" $3) in v) { C += $4; S += $5; n++
      t = substr($6, 1, 50); sub(/[\300-\377][\200-\277]*$/, "", t)   # fara litera taiata pe jumatate
      printf "%d\t%s poz %s\t%d cifre, %d superlative\t%s\n", $4 + 2 * $5, $1, $3, $4, $5, t }
    END { printf "TOTAL\t%d\t%d\t%d\n", n, C, S > "/dev/stderr" }
  ' "$W/risc" 2> "$W/risct" | LC_ALL=C sort -t "$TAB" -k1,1nr > "$W/riscs"
  set -- $(cut -f2- "$W/risct" | tr '\t' ' ')
  if [ -s "$W/riscs" ]; then
    atentie "in $1 capitole RO neverificate: $2 cifre si $3 superlative — primele 10, unde se sapa intai:"
    head -10 "$W/riscs" | awk -F'\t' '{ printf "             %-22s %-26s %s\n", $2, $3, $4 }'
  else
    ok "toate capitolele RO sunt verificate la sursa"
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 20 "Dovezile afirmatiilor: nivelul sursei, adresa, cine a citit-o"
# ════════════════════════════════════════════════════════════════════
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
SURSE="$SCRIPT_DIR/surse.tsv"; SDAT="$SCRIPT_DIR/surse-datorie.txt"
if [ ! -f "$SURSE" ] || [ ! -f "$SDAT" ]; then
  problema "lipseste scripts/surse.tsv sau scripts/surse-datorie.txt"
else
  grep -v '^#' "$SURSE" | grep -v '^[[:space:]]*$' > "$W/sr"
  grep -v '^#' "$SDAT" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u > "$W/sd"
  AZI=$(date +%Y-%m-%d)
  awk -F'\t' -v AF="$W/af" -v SD="$W/sd" -v AZI="$AZI" '
    function dom(u,  d) { d = u; sub(/^https:\/\//, "", d); sub(/\/.*/, "", d); sub(/^www\./, "", d); return d }
    BEGIN { while ((getline l < AF) > 0) { split(l, x, "\t"); et[x[1]] = x[2]; st[x[1]] = x[3] }
            while ((getline l < SD) > 0) dat[l] = 1 }
    NF != 6 { print "surse.tsv rand " NR ": " NF " coloane, trebuie 6"; next }
    { for (i = 1; i <= 6; i++) if ($i ~ /^[[:space:]]*$/) { print "surse.tsv rand " NR ": coloana " i " goala (se scrie -)"; next } }
    !($1 in et) { print "surse.tsv: \"" $1 "\" nu e in afirmatii.tsv"; next }
    $2 !~ /^[PST]$/ { print "surse.tsv " $1 ": nivel \"" $2 "\" — P, S sau T" }
    $3 !~ /^https:\/\/[^ ]+\.[^ ]+/ { print "surse.tsv " $1 ": adresa \"" $3 "\" — trebuie https://..." }
    $4 !~ /^20[0-9][0-9]-[01][0-9]-[0-3][0-9]$/ { print "surse.tsv " $1 ": accesat \"" $4 "\" — AAAA-LL-ZZ" }
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
    }' "$W/sr" > "$W/srerr"
  grep -v '^STAT	' "$W/srerr" | grep -v '^DATORIE-STINSA	' > "$W/srp"
  if [ -s "$W/srp" ]; then
    while IFS= read -r l; do problema "$l"; done < "$W/srp"
  else
    set -- $(grep '^STAT	' "$W/srerr" | cut -f2- | tr '\t' ' ')
    ok "$1 afirmatii cu dovezi in surse.tsv, toate cu sursa suficienta; citite doar de Claude: $2, si de un om: $3; fara citat exact: $4"
  fi
  grep '^DATORIE-STINSA	' "$W/srerr" | cut -f2 | while IFS= read -r i; do atentie "surse-datorie.txt: \"$i\" are acum dovezi suficiente — scoate-l din datorie"; done
  nd=$(wc -l < "$W/sd" | tr -d ' ')
  [ "$nd" -gt 0 ] && atentie "$nd afirmatii verificate inainte de pas67, inca fara dovezi in surse.tsv (datoria; scade, nu creste)"
fi

# ════════════════════════════════════════════════════════════════════
titlu 21 "Erorile gasite: tipurile, ca sa stim unde sa cautam"
# ════════════════════════════════════════════════════════════════════
# Din pas67.  scripts/erori.tsv — o eroare gasita si corectata = un rand (TAB):
#   pas  id  poz  tip  descriere  sursa
#   tip: superlativ | atribuire | cifra | cronologie | atenuare | traducere | contradictie | alta
#   poz: pozitia <h2> (ca in capitole-verificate.tsv) sau "-"; sursa: https://... sau "-"
# Nu blocheaza decat un rand stricat; altfel numara erorile pe tipuri.
ERORI="$SCRIPT_DIR/erori.tsv"
if [ ! -f "$ERORI" ]; then
  problema "lipseste scripts/erori.tsv"
else
  grep -v '^#' "$ERORI" | grep -v '^[[:space:]]*$' > "$W/er"
  awk -F'\t' -v MF="$W/m" '
    BEGIN { while ((getline l < MF) > 0) { split(l, x, "\t"); doc[x[1]] = 1 } }
    NF != 6 { print "erori.tsv rand " NR ": " NF " coloane, trebuie 6"; next }
    $1 !~ /^pas[0-9]+[a-z]?$/ { print "erori.tsv rand " NR ": pas \"" $1 "\"" }
    !($2 in doc) { print "erori.tsv rand " NR ": \"" $2 "\" nu e in manifest" }
    $3 != "-" && $3 !~ /^[1-9][0-9]*$/ { print "erori.tsv rand " NR ": poz \"" $3 "\"" }
    $4 !~ /^(superlativ|atribuire|cifra|cronologie|atenuare|traducere|contradictie|alta)$/ { print "erori.tsv rand " NR ": tip \"" $4 "\"" }
    $5 ~ /^[[:space:]]*-?[[:space:]]*$/ { print "erori.tsv rand " NR ": fara descriere" }
    $6 != "-" && $6 !~ /^https:\/\// { print "erori.tsv rand " NR ": sursa \"" $6 "\" — https://... sau -" }
  ' "$W/er" > "$W/ererr"
  if [ -s "$W/ererr" ]; then
    while IFS= read -r l; do problema "$l"; done < "$W/ererr"
  else
    ok "$(wc -l < "$W/er" | tr -d ' ') erori gasite si corectate, pe tipuri: $(cut -f4 "$W/er" | LC_ALL=C sort | uniq -c | sort -rn | awk '{ printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')"
  fi
fi

# ════════════════════════════════════════════════════════════════════
titlu 22 "Text ascuns si instructiuni pentru masini (prompt injection)"
# ════════════════════════════════════════════════════════════════════
# Din pas68.  Slabiciunea cunoscuta: asistentul citeste pagini straine, iar o pagina
# poate ascunde instructiuni pentru masini; un text copiat de acolo poate duce pe site
# caractere invizibile sau continut ascuns.  Scriptul nu poate elimina riscul — il
# poate face vizibil, la fiecare push.  Masurat intai (24 oct): zero continut ascuns,
# zero caractere de felul acesta (o singura cratima discreta U+00AD, tipografie, permisa).
#   PROBLEMA  caractere invizibile in pagini sau in scripts/*.tsv, *.txt:
#             zero-width (U+200B-200F), control bidi (U+202A-202E, U+2066-2069),
#             U+2060-2064, BOM (U+FEFF), etichete Unicode (U+E0000-E007F)
#   PROBLEMA  element ascuns in pagina: atributul hidden, sau style= cu display:none,
#             visibility:hidden, font-size:0, opacity:0
#   ATENTIE   reguli CSS care ascund (pot fi legitime: meniuri, tiparire); pseudo-elementele
#             ::before / ::after (decor, fara textul paginii) sunt lasate deoparte
#   ATENTIE   fraze adresate masinilor („ignore previous instructions”, „system prompt”…),
#             oriunde in fisier — si in comentarii, atribute, registre
: > "$W/invpat"
for c in 213 214 215 216 217; do printf "\\342\\200\\$c\n" >> "$W/invpat"; done
for c in 252 253 254 255 256; do printf "\\342\\200\\$c\n" >> "$W/invpat"; done
for c in 240 241 242 243 244 246 247 250 251; do printf "\\342\\201\\$c\n" >> "$W/invpat"; done
printf '\357\273\277\n' >> "$W/invpat"
for x in 0 1 2 3 4 5 6 7; do for y in 0 1 2 3 4 5 6 7; do
  printf "\\363\\240\\200\\2$x$y\n" >> "$W/invpat"; printf "\\363\\240\\201\\2$x$y\n" >> "$W/invpat"
done; done
cat > "$W/injpat" <<'PAT'
ignore previous instructions
ignore all previous instructions
ignore the previous instructions
ignore the above instructions
disregard previous instructions
disregard the above
system prompt
you are chatgpt
you are claude
as an ai language model
<system>
</system>
[inst]
ignoră instrucțiunile
ignora instructiunile
ignorer tidligere instruksjoner
glem tidligere instruksjoner
PAT
: > "$W/fis22"
cat "$W/html" >> "$W/fis22"
find "$SCRIPT_DIR" -maxdepth 1 -type f \( -name '*.tsv' -o -name '*.txt' \) | sort >> "$W/fis22"
: > "$W/p22"; : > "$W/a22"
while IFS= read -r f; do
  rel=${f#"$RADACINA"/}
  LC_ALL=C grep -n -F -f "$W/invpat" "$f" 2>/dev/null | cut -d: -f1 | while IFS= read -r n; do
    echo "$rel, randul $n: caracter invizibil (zero-width, bidi, BOM sau eticheta Unicode)"; done >> "$W/p22"
  LC_ALL=C grep -n -i -F -f "$W/injpat" "$f" 2>/dev/null | cut -d: -f1 | while IFS= read -r n; do
    echo "$rel, randul $n: fraza adresata masinilor — de citit"; done >> "$W/a22"
done < "$W/fis22"
while IFS= read -r f; do
  rel=${f#"$RADACINA"/}
  # elemente ascunse: din tag-urile reale (style=), plus atributul hidden (fara valoare, din textul brut)
  awk -F'\t' -v r="$rel" '{ for (i = 2; i < NF; i += 2) if ($i == "style") { v = tolower($(i + 1))
      if (v ~ /display *: *none|visibility *: *hidden|font-size *: *0(px|pt|em|rem|%)? *(;|$)|opacity *: *0(\.0*)? *(;|$)/) print r ": <" $1 " style=\"" $(i + 1) "\"> — element ascuns" } }' "$(tagsf "$f")" >> "$W/p22"
  LC_ALL=C awk '/<style/{s=1} /<\/style>/{s=0;next} /<script/{c=1} /<\/script>/{c=0;next} !s && !c' "$f" \
    | LC_ALL=C grep -n -i -E '<[a-z][a-z0-9]*[^>]*[[:space:]]hidden([[:space:]>=]|$)' | cut -d: -f1 \
    | while IFS= read -r n; do echo "$rel: element cu atributul hidden (in textul fara style si script, randul $n)"; done >> "$W/p22"
  # reguli CSS care ascund: legitime uneori, deci doar semnalate
  LC_ALL=C awk '/<style/{s=1} s{print} /<\/style>/{s=0}' "$f" | tr '\n' ' ' | LC_ALL=C tr 'A-Z' 'a-z' \
    | LC_ALL=C grep -o -E '[^{}]*\{[^}]*(display *: *none|visibility *: *hidden|font-size *: *0(px|pt|em|rem|%)? *(;|\})|opacity *: *0(\.0*)? *(;|\}))' \
    | sed 's/{.*//' | grep -v -e '::before' -e '::after' \
    | while IFS= read -r sel; do echo "$rel: regula CSS care ascunde:$sel"; done >> "$W/a22"
done < "$W/html"
if [ -s "$W/p22" ]; then
  while IFS= read -r l; do problema "$l"; done < "$W/p22"
else
  ok "$(wc -l < "$W/fis22" | tr -d ' ') fisiere citite: niciun caracter invizibil, niciun element ascuns"
fi
if [ -s "$W/a22" ]; then
  atentie "$(wc -l < "$W/a22" | tr -d ' ') locuri de citit (CSS care ascunde sau fraze adresate masinilor):"
  sed 's/^/             /' "$W/a22"
else
  ok "nicio fraza adresata masinilor, nicio regula CSS care ascunde"
fi

# ── modul --surse (pas68): citatele exacte confruntate cu pagina lor, prin retea ──
# Pentru fiecare rand cu citat: pagina se descarca (curl, sau ftp(1) pe OpenBSD), se
# reduce la litere si cifre (fara tag-uri, entitati, punctuatie, ghilimele, spatii) si
# se cauta citatul redus la fel.  Negasit sau inaccesibil = ATENTIE (paginile se schimba,
# unele se incarca prin JavaScript); pagina cu text ascuns sau fraze pentru masini = ATENTIE.
# NORGEDAN_SURSE_DIR=dir: paginile se iau de acolo (<cksum-url>.html), fara retea (teste).
if [ "$MOD" = surse ]; then
  cat > "$W/red.awk" <<'AWK'
BEGIN { RS = "\001" }
{ t = tolower($0); gsub(/&[a-z0-9#]+;/, "", t)
gsub(/\302\253|\302\273|\302\240|\342\200\236|\342\200\235|\342\200\234|\342\200\230|\342\200\231|\342\200\223|\342\200\224|\342\200\246/, "", t)
gsub(/[^a-z0-9\200-\377]/, "", t); printf "%s", t }
AWK
  # pagina din retea e adesea minificata (tot HTML-ul pe 1-20 de randuri, cu <script> in
  # mijlocul textului): text_normalizat, care lucreaza pe randuri, ar pierde textul.  Aici
  # fisierul se citeste intreg si se sar comentariile, <script>, <style> si tag-urile.
  # pas70: o singura impartire la „<”, apoi o trecere — liniar.  Varianta din pas68 copia
  # restul paginii la fiecare tag: pe awk-ul OpenBSD, 2 minute pentru o pagina Eurostat de
  # 700 KB (one-true-awk, masurat); acum 0,13 s, cu acelasi text redus, pe 4 awk-uri.
  cat > "$W/pag.awk" <<'AWK'
BEGIN { RS = "\001" }
{ t = $0; gsub(/[\n\r\t]/, " ", t)
  n = split(t, a, "<"); printf "%s", a[1]; m = ""
  for (i = 2; i <= n; i++) {
    s = a[i]
    if (m == "c") { k = index(s, "-->"); if (k) { printf " %s", substr(s, k + 3); m = "" }; continue }
    l = tolower(substr(s, 1, 8))
    if (m != "") { if (substr(l, 1, length(m) + 1) == "/" m) { k = index(s, ">"); if (k) printf " %s", substr(s, k + 1); m = "" }; continue }
    if (substr(s, 1, 3) == "!--") { k = index(substr(s, 4), "-->"); if (k) printf " %s", substr(s, k + 6); else m = "c"; continue }
    if (l ~ /^script([ >\/]|$)/) { m = "script"; continue }
    if (l ~ /^style([ >\/]|$)/) { m = "style"; continue }
    k = index(s, ">"); if (k) printf " %s", substr(s, k + 1)
  }
}
AWK
  # pas70: limita totala de timp pe pagina (implicit 45 s, NORGEDAN_SURSE_TIMEOUT), si
  # pentru ftp(1), al carui -w limiteaza doar conectarea.  Descarcarea porneste in fundal;
  # un paznic o opreste la limita.  Paznicul e un subshell: oprit el, kill-ul lui nu mai
  # ruleaza (doar un sleep orfan, inofensiv, isi termina somnul).
  ST=${NORGEDAN_SURSE_TIMEOUT:-45}
  sursa_ia() {
    if [ -n "${NORGEDAN_SURSE_DIR:-}" ] && [ -d "$NORGEDAN_SURSE_DIR" ]; then
      k=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
      [ -f "$NORGEDAN_SURSE_DIR/$k.html" ] && cp "$NORGEDAN_SURSE_DIR/$k.html" "$2"
      return 0
    fi
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -m "$ST" -A "Mozilla/5.0" -o "$2" "$1" 2>/dev/null &
    else
      ftp -V -M -w 30 -U "Mozilla/5.0" -o "$2" "$1" >/dev/null 2>&1 &
    fi
    dp=$!
    ( sleep "$ST" && kill "$dp" 2>/dev/null ) &
    pz=$!
    wait "$dp" 2>/dev/null; rz=$?
    kill "$pz" 2>/dev/null; wait "$pz" 2>/dev/null
    [ "$rz" -eq 0 ] || rm -f "$2"
  }
  # pas72: o pagina-capcana anti-robot raspunde cu 200, dar fara articol (OSW, 25 oct.:
  # reCAPTCHA).  Daca citatul lipseste si pagina are semnele unei asemenea verificari,
  # se spune asta — nu „citatul nu (mai) e in pagina”, care ar acuza sursa pe nedrept.
  # Semnele se cauta doar cand citatul lipseste: o pagina reala poate contine un widget.
  cat > "$W/botpat" <<'PAT'
RecaptchaChallengePageUi
challenge-platform
cf-chl-
<title>Just a moment...</title>
Attention Required! | Cloudflare
captcha-delivery.com
_Incapsula_Resource
px-captcha
AwsWafIntegration
Checking your browser
PAT
  ng=0; nn=0; ni=0; nb=0
  awk -F'\t' '$6 != "-"' "$W/sr" > "$W/src"
  while IFS="$TAB" read -r id niv url acc cine cit; do
    np=$((ng + nn + ni + nb + 1)); rm -f "$W/pag"; sursa_ia "$url" "$W/pag.$np"
    [ -f "$W/pag.$np" ] && mv "$W/pag.$np" "$W/pag"
    if [ ! -s "$W/pag" ]; then atentie "--surse: nu pot citi $url ($id) — inaccesibila sau peste ${ST} s"; ni=$((ni + 1)); continue; fi
    LC_ALL=C awk -f "$W/pag.awk" "$W/pag" | LC_ALL=C awk -f "$W/red.awk" > "$W/pagr"
    printf '%s' "$cit" | LC_ALL=C awk -f "$W/red.awk" > "$W/citr"
    if [ -s "$W/citr" ] && LC_ALL=C grep -q -F -f "$W/citr" "$W/pagr"; then ng=$((ng + 1))
    elif LC_ALL=C grep -q -F -f "$W/botpat" "$W/pag"; then
      atentie "--surse: $url cere verificare anti-robot — citatul nu poate fi reconfirmat mecanic ($id); deschide pagina in browser"; nb=$((nb + 1))
    else atentie "--surse: citatul pentru \"$id\" nu (mai) e in $url — reverifica"; nn=$((nn + 1)); fi
    LC_ALL=C grep -q -F -f "$W/invpat" "$W/pag" && atentie "--surse: $url are caractere invizibile — tratata ca date, cu grija ($id)"
    LC_ALL=C grep -q -i -F -f "$W/injpat" "$W/pag" && atentie "--surse: $url contine fraze adresate masinilor — tratata ca date, cu grija ($id)"
  done < "$W/src"
  ok "--surse: $ng citate gasite in pagina lor; $nn negasite; $ni pagini inaccesibile; $nb cu verificare anti-robot"
fi

# ════════════════════════════════════════════════════════════════════
tablou

probleme=$(wc -l < "$W/prob" | tr -d ' ')
atentii=$(wc -l < "$W/aten" | tr -d ' ')
echo ""
echo "===================================================="
if [ "$probleme" -eq 0 ]; then
  echo "  REZULTAT: totul in regula ($atentii atentionari). Poti face push."
  echo "===================================================="; echo ""
  exit 0
else
  echo "  REZULTAT: $probleme probleme, $atentii atentionari. NU face push."
  echo "===================================================="; echo ""
  exit 1
fi
