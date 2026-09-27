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
TAB=$(printf '\t')

MOD=manual
PUSH_REPO=""
case "${1:-}" in
  "")        ;;
  --tablou)  MOD=tablou ;;
  --github)  MOD=github ;;
  --ci)      MOD=ci ;;
  --push)    MOD=push; PUSH_REPO="${2:-}" ;;
  *)         echo "utilizare: sh $0 [--tablou | --github | --ci | --push <repo>]" >&2; exit 2 ;;
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

# cuvinte intr-un fisier — aceeasi metoda ca in v2, ca cifrele sa ramana comparabile
cuvinte() {
  awk '/<style>/{s=1} /<\/style>/{s=0;next} !s' "$1" | sed 's/<[^>]*>//g' \
    | LC_ALL="$LOCALE_NUM" wc -w | tr -d ' '
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
  echo "  numarat fara CSS si tag-uri, locale $LOCALE_NUM"
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
  sed -n 's|.*<loc>\([^<]*\)</loc>.*|\1|p' "$sm" | while read -r u; do
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
  gasit=0
  while read -r tipar; do
    : > "$W/hit"
    while read -r f; do grep -qF -- "$tipar" "$f" && echo "${f#"$RADACINA"/}" >> "$W/hit"; done < "$W/pub"
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
  sed 's/<[^>]*>/ /g; s/[("*>]/ /g; s/„/ /g; s/”/ /g; s/«/ /g; s/»/ /g' "$1" | awk -f "$W/nr.awk"
}

rot()  { echo $(( ($1 + 500) / 1000 * 1000 )); }
jos()  { echo $(( $1 / 1000 * 1000 )); }

verifica_cuv() {   # <fisier> <valoare-masurata> <eticheta>
  grep -oE "$RE_CUV" "$1" 2>/dev/null | while read -r dec; do
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
  for tag in html head body section blockquote div; do
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
      case "$b" in robots.txt|sitemap-hub.xml) continue ;; esac
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
[ "$greseli" -eq 0 ] && ok "nicio clona in urma fata de GitHub; arborii verificati sunt cei care se publica"

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
  greseli=0
  while read -r repo; do
    linie=$(awk -F'\t' -v r="$repo" '$1==r' "$W/about")
    if [ -z "$linie" ]; then problema "$repo: nu are rand in scripts/about.tsv"; greseli=1; continue; fi
    printf '%s\n' "$linie" | awk -F'\t' 'NF!=4 {exit 1}' || { problema "$repo: randul din about.tsv nu are 4 coloane"; greseli=1; continue; }
    d_ok=$(printf '%s\n' "$linie" | cut -f2); w_ok=$(printf '%s\n' "$linie" | cut -f3)
    t_ok=$(printf '%s\n' "$linie" | cut -f4 | tr ',' '\n' | grep -v '^$' | sort | tr '\n' ',')
    if ! api_get "$repo" "$W/api.json" || ! grep -q '"full_name"' "$W/api.json"; then
      atentie "$repo: pagina GitHub nu poate fi citita acum (retea sau limita API) — verificare sarita"; continue
    fi
    d=$(json_str description "$W/api.json"); w=$(json_str homepage "$W/api.json"); t=$(topics_of "$W/api.json")
    [ "$d" = "$d_ok" ] || { problema "$repo: descrierea de pe GitHub difera de about.tsv"; echo "             GitHub:    ${d:-(goala)}"; echo "             about.tsv: $d_ok"; greseli=1; }
    [ "$w" = "$w_ok" ] || { problema "$repo: website-ul de pe GitHub e \"${w:-gol}\", trebuie $w_ok"; greseli=1; }
    [ "$t" = "$t_ok" ] || { problema "$repo: topics pe GitHub [${t%,}], trebuie [${t_ok%,}]"; greseli=1; }
    for f in has_wiki has_projects; do
      [ "$(json_bool $f "$W/api.json")" = "false" ] || { problema "$repo: ${f#has_} activ pe GitHub, dar nefolosit — Settings, Features"; greseli=1; }
    done
    sp=$(json_str spdx_id "$W/api.json")
    [ "$sp" = "CC-BY-4.0" ] || atentie "$repo: GitHub vede licenta ca \"${sp:-nimic}\" — daca LICENSE tocmai s-a schimbat, GitHub o recalculeaza dupa push"
  done < "$W/repos"
  awk -F'\t' '{print $1}' "$W/about" | while read -r r; do
    grep -qxF "$r" "$W/repos" || echo "$r"
  done > "$W/aboutx"
  while read -r r; do problema "about.tsv are rand pentru $r, care nu e repo al site-ului"; greseli=1; done < "$W/aboutx"
  [ "$greseli" -eq 0 ] && ok "paginile GitHub corespund about.tsv (descriere, website, topics, fara wiki/projects)"
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
