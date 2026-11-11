#!/bin/sh
# pazitor.sh (pas141) — sigiliul lui Bogdan: garda pazita din afara ei.
#
# Garda nu se poate verifica pe ea insasi: un verifica-site.sh schimbat ar putea sari
# orice verificare, iar un martor livrat prin patch e scris de acelasi care a scris
# patch-ul.  De aceea paznicul si sigiliul stau IN AFARA repo-urilor, in
# <radacina clonelor>/.norgedan/ — unde nu ajunge niciun patch (aplica.sh lucreaza doar
# in clone) — iar sigiliul il rescrie doar omul, cu mana lui, dupa ce a vazut ce s-a schimbat.
#
#   .norgedan/pazitor.sh      copia INSTALATA a acestui fisier (ea ruleaza, nu cea din hub)
#   .norgedan/hooks/pre-push  poarta: fiecare clona are core.hooksPath spre acest director
#   .norgedan/sigiliu.tsv     amprentele sha256 ale scripturilor garzii:  cale <TAB> amprenta
#
# Ce pazeste: tot ce hotaraste daca un push trece — scripts/*.sh, *.awk, *.py, hook-ul,
# regulile cu registrul lor si workflow-ul CI, toate din hub.  Registrele de date (*.tsv
# din scripts/) NU: se schimba la fiecare pas de continut si le pazeste garda insasi.
#
#   sh scripts/pazitor.sh --instaleaza      (din hub, o data, dupa ce ai CITIT fisierul)
#        copiaza paznicul in .norgedan/ si scrie poarta; nu sigileaza si nu atinge clonele
#   sh .norgedan/pazitor.sh --sigileaza     arata ce s-a schimbat de la ultima sigilare,
#        cere „da” si abia apoi rescrie sigiliul
#   sh .norgedan/pazitor.sh --verifica      compara, fara sa scrie; iesire 0 = neschimbat,
#        1 = schimbat (lista pe iesire), 2 = nesigilat sau hub lipsa
#   (la push, chemat de poarta)  --push     verifica; neschimbat -> da mai departe garzii
#        din clona (scripts/hooks/pre-push); altfel OPRESTE push-ul
#
# Limite, spuse: nu apara de un calculator compromis (cine scrie in radacina poate rescrie
# si sigiliul) si nu exista in CI.  Sigiliul e atat de bun cat e privirea celui care il pune.
# POSIX: sh, awk, sort, cmp, cp, mkdir, chmod, sha256 (OpenBSD) sau sha256sum (Linux).
LC_ALL=C; export LC_ALL
D=$(cd "$(dirname "$0")" && pwd)
sha() { if command -v sha256 >/dev/null 2>&1; then sha256 -q "$1"; else sha256sum "$1" | cut -d' ' -f1; fi; }

MOD=${1:-}
if [ "$MOD" = --instaleaza ]; then
  # rulat din hub: D = <radacina>/norgedan.github.io/scripts
  R=$(dirname "$(dirname "$D")"); N="$R/.norgedan"
  [ -f "$D/verifica-site.sh" ] || { echo "pazitor: --instaleaza se ruleaza din hub: sh scripts/pazitor.sh --instaleaza" >&2; exit 2; }
  mkdir -p "$N/hooks" || exit 1
  cp "$D/pazitor.sh" "$N/pazitor.sh" || exit 1
  printf '%s\n' '#!/bin/sh' '# poarta norgedan (scrisa de pazitor.sh --instaleaza): intai sigiliul, apoi garda' \
    'exec sh "$(dirname "$0")/../pazitor.sh" --push "$@"' > "$N/hooks/pre-push" || exit 1
  chmod +x "$N/hooks/pre-push" || exit 1
  echo "  Instalat: $N/pazitor.sh si $N/hooks/pre-push"
  echo "  Urmeaza, cu mana ta:"
  echo "    1. sigiliul:  sh $N/pazitor.sh --sigileaza"
  echo "    2. poarta, in fiecare clona publica:  cd <clona> && git config core.hooksPath $N/hooks"
  exit 0
fi

# de aici: copia instalata — D = <radacina>/.norgedan
HUB="$(dirname "$D")/norgedan.github.io"; S="$D/sigiliu.tsv"
T=$(mktemp -d /tmp/pazitor.XXXXXX) || exit 1
trap 'rm -rf "$T"' EXIT
trap 'exit 1' INT TERM HUP

acum() {
  ( cd "$HUB" || exit 1
    for f in scripts/*.sh scripts/*.awk scripts/*.py scripts/hooks/* scripts/reguli/* .github/workflows/*.yml; do
      [ -f "$f" ] && printf '%s\n' "$f"
    done | sort ) > "$T/lista"
  while IFS= read -r f; do printf '%s\t%s\n' "$f" "$(sha "$HUB/$f")"; done < "$T/lista" > "$T/acum"
  [ -s "$T/acum" ]
}
# deosebiri <sigiliu> <acum> — un rand pentru fiecare fisier schimbat, nou sau disparut
deosebiri() {
  awk -F'\t' 'NR == FNR { v[$1] = $2; next }
    { n[$1] = 1; if (!($1 in v)) print "    nou:       " $1; else if (v[$1] != $2) print "    schimbat:  " $1 }
    END { for (f in v) if (!(f in n)) print "    disparut:  " f }' "$1" "$2" | sort
}
[ -f "$HUB/scripts/verifica-site.sh" ] || { echo "pazitor: nu gasesc hub-ul ($HUB)" >&2; exit 2; }
acum || { echo "pazitor: n-am gasit niciun script de pazit in $HUB" >&2; exit 2; }

case $MOD in
--verifica)
  [ -s "$S" ] || { echo "    nesigilat: $S lipseste"; exit 2; }
  cmp -s "$S" "$T/acum" && exit 0
  deosebiri "$S" "$T/acum"; exit 1 ;;
--sigileaza)
  if [ -s "$S" ] && cmp -s "$S" "$T/acum"; then echo "  Sigiliul e la zi: $(wc -l < "$S" | tr -d ' ') fisiere, neschimbate."; exit 0; fi
  if [ -s "$S" ]; then echo "  De la ultima sigilare:"; deosebiri "$S" "$T/acum"
  else echo "  Prima sigilare: $(wc -l < "$T/acum" | tr -d ' ') fisiere:"; cut -f1 "$T/acum" | sed 's/^/    /'; fi
  echo ""
  printf '  Ai vazut ce s-a schimbat si vrei sa sigilezi? Scrie da: '
  read -r r || r=
  [ "$r" = da ] || { echo "  Nesigilat — nimic scris."; exit 1; }
  cp "$T/acum" "$S.nou.$$" && mv "$S.nou.$$" "$S" || { rm -f "$S.nou.$$"; echo "pazitor: sigiliul nu a putut fi scris" >&2; exit 1; }
  echo "  Sigilat: $(wc -l < "$S" | tr -d ' ') fisiere, in $S"
  exit 0 ;;
--push)
  shift
  top=$(git rev-parse --show-toplevel) || exit 1
  if [ ! -s "$S" ]; then
    echo "pazitor: garda nu e sigilata — push oprit.  Sigileaza: sh $D/pazitor.sh --sigileaza" >&2; exit 1
  fi
  if ! cmp -s "$S" "$T/acum"; then
    echo "" >&2
    echo "pazitor: scripturile garzii s-au schimbat de la ultima sigilare — PUSH OPRIT:" >&2
    deosebiri "$S" "$T/acum" >&2
    echo "  Daca schimbarea e cea asteptata (ai aplicat un patch care le atinge):" >&2
    echo "    sh $D/pazitor.sh --sigileaza" >&2
    echo "  Daca nu te asteptai la ea: nu sigila; spune-i lui Claude ce vezi." >&2
    exit 1
  fi
  [ -f "$top/scripts/hooks/pre-push" ] || { echo "pazitor: $top nu are scripts/hooks/pre-push" >&2; exit 1; }
  rm -rf "$T"; trap - EXIT
  exec sh "$top/scripts/hooks/pre-push" "$@" ;;
*) echo "utilizare: sh $0 --sigileaza | --verifica      (din hub, o data: sh scripts/pazitor.sh --instaleaza)" >&2; exit 2 ;;
esac
