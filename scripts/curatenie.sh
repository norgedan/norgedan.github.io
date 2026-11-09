#!/bin/sh
# curatenie.sh (pas132) — rutina de curatenie, regula 24.  DOAR LISTEAZA.
#
# Nu sterge nimic: o stergere nu se ia inapoi, deci o face doar Bogdan, dupa ce
# citeste lista.  Ruleaza la rularea saptamanala:  sh scripts/verifica-site.sh --curatenie
#
# Ce cauta:
#   [c1] in repo-uri: fisiere neurmarite de git (ca acel „main” gol din pas123), resturi
#        de editare (*.orig, *.rej, *~, .DS_Store), ramuri locale in afara de main, stash-uri
#   [c2] pe site: imagini, PDF-uri, scripturi si stiluri urmarite de git, dar spre care
#        nu trimite nimic (niciun fisier text din niciun repo nu le numeste)
#   [c3] pe masina: patch-uri vechi in Descarcari, directoare temporare ramase de la
#        rulari intrerupte (/tmp/verifica-site.*, teste-garda.*, dovezi.*, legaturi.*, mostra.*)
#
# POSIX: sh, git, find, awk, sed, grep.  Iesirea: „DE CITIT” pe rand, apoi totalul.
LC_ALL=C; export LC_ALL
SD=$(cd "$(dirname "$0")" && pwd)
HUB=$(dirname "$SD")
RADACINA=${RADACINA:-$(dirname "$HUB")}
HUBNAME=$(basename "$HUB")
DESCARCARI=${DESCARCARI:-$RADACINA/Downloads}
TMPD=${TMPD:-/tmp}
W=$(mktemp -d /tmp/curatenie.XXXXXX) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

{ echo "$HUBNAME"; awk -F'\t' '!/^#/ && NF >= 7 { print $3 }' "$SD/documente.tsv"; } | awk '!v[$0]++' > "$W/repos"
[ -d "$RADACINA/norgedan-jurnal/.git" ] && echo norgedan-jurnal >> "$W/repos"
[ -s "$W/repos" ] || { echo "curatenie.sh: nicio clona citita din documente.tsv (santinela)" >&2; exit 1; }

n=0
spune() { echo "  DE CITIT  $1"; n=$((n + 1)); }

echo ""
echo "[c1] Repo-uri: fisiere ratacite, resturi, ramuri"
while read -r r; do
  d="$RADACINA/$r"; [ -d "$d/.git" ] || { spune "$r: clona lipseste din $RADACINA"; continue; }
  git -C "$d" status --porcelain --untracked-files=all 2>/dev/null | sed -n 's/^?? //p' > "$W/nu"
  while read -r f; do spune "$r/$f — neurmarit de git (nu e publicat): de pastrat, de comis sau de sters?"; done < "$W/nu"
  git -C "$d" ls-files | grep -E '(\.orig|\.rej|~|\.DS_Store)$' | while read -r f; do echo "$r/$f"; done > "$W/rest"
  while read -r f; do spune "$f — rest de editare, urmarit de git"; done < "$W/rest"
  git -C "$d" for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$' > "$W/ram"
  while read -r b; do spune "$r: ramura locala „$b” (in afara de main)"; done < "$W/ram"
  s=$(git -C "$d" stash list 2>/dev/null | wc -l | tr -d ' ')
  [ "$s" -gt 0 ] && spune "$r: $s stash-uri uitate (git stash list)"
done < "$W/repos"

echo ""
echo "[c2] Site: fisiere publicate spre care nu trimite nimic"
: > "$W/active"; : > "$W/text"
while read -r r; do
  d="$RADACINA/$r"; [ -d "$d/.git" ] || continue
  [ "$r" = norgedan-jurnal ] && continue
  git -C "$d" ls-files | while read -r f; do
    case "$f" in *.js|*.css) echo "$d/$f" >> "$W/text" ;; esac
    case "$f" in
      *.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.ico|*.pdf|*.mp3|*.ogg|*.js|*.css|*.woff|*.woff2) echo "$r/$f" >> "$W/active" ;;
      # doar fisierele care se publica si pot trimite spre ceva; nu scripturile si registrele
      # garzii (suita de teste numeste fisiere inventate, ca sa le caute)
      *.html|*.xml|*.js|*.css|*.md|*.json|*.yml|*.yaml|*.webmanifest) echo "$d/$f" >> "$W/text" ;;
    esac
  done
done < "$W/repos"
while read -r a; do
  b=$(basename "$a")
  # numele cautat ca atare in toate fisierele text; un fisier nu se numara pe sine
  if ! grep -lF -- "$b" $(cat "$W/text") 2>/dev/null | grep -v -F -x -- "$RADACINA/$a" | grep -q .; then
    spune "$a — nimic nu trimite spre el"
  fi
done < "$W/active"

echo ""
echo "[c3] Masina: patch-uri vechi si directoare temporare ramase"
if [ -d "$DESCARCARI" ]; then
  find "$DESCARCARI" -maxdepth 1 -type f -name 'pas*.patch' 2>/dev/null | sort > "$W/pt"
  while read -r f; do spune "$f — patch deja aplicat? (rm /home/bogdan/Downloads/pas*.patch inainte de urmatoarea descarcare)"; done < "$W/pt"
fi
for p in 'verifica-site.*' 'teste-garda.*' 'dovezi.*' 'legaturi.*' 'curatenie.*' 'mostra.*'; do
  find "$TMPD" -maxdepth 1 -type d -name "$p" -mtime +0 2>/dev/null
done | sort > "$W/tm"
while read -r f; do spune "$f — director temporar mai vechi de o zi (o rulare intrerupta)"; done < "$W/tm"

echo ""
if [ "$n" -eq 0 ]; then echo "  CURAT     nimic de citit: repo-uri, site si masina in ordine"
else echo "  TOTAL     $n de citit — nimic nu s-a sters; sterge doar Bogdan, dupa ce citeste"; fi
exit 0
