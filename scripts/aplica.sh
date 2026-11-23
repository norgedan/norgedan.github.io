#!/bin/sh
# aplica.sh — aplica un patch livrat de Claude, cu toate verificarile, FARA commit (pas102).
#
#   sh ~/norgedan.github.io/scripts/aplica.sh ~/norgedan.github.io /home/bogdan/Downloads/pas102-hub.patch SHA256
#
# Face, in ordine, exact pasii procedurii manuale si se opreste la primul care nu trece:
#   1. amprenta sha256 a fisierului == cea din discutie (al treilea argument)
#   2. arborele repo-ului e curat (git status --short gol)
#   3. git apply --check, apoi git apply (o singura data)
#   4. git add -A, apoi git diff --cached --raw comparat cu randurile „# raw: ” din antetul
#      patch-ului (textul dinaintea primului „diff --git”, pe care git apply il ignora)
# pas181: intre 1 si 2, liniile ADAUGATE de patch sunt citite cu tiparele garzii
# (scripts/injectii.sh): un caracter invizibil opreste totul, inainte sa se schimbe ceva;
# frazele adresate masinilor si literele din alfabete amestecate sunt aratate (ATENTIE),
# cu fisierul si randul din patch - de citit inainte de commit.  Un patch care schimba
# chiar tiparele sau testele lor le contine legitim: atunci ATENTIE e de asteptat.
# Commit-ul si push-ul raman ale lui Bogdan: scriptul doar pregateste si spune ce a vazut.
# Portabil POSIX: OpenBSD (sha256 -q) si Linux (sha256sum).
[ $# -eq 3 ] || { echo "utilizare: sh $0 <repo> <patch> <sha256>" >&2; exit 2; }
r=$1; p=$2; h=$3
case $p in /*) ;; *) p=$(pwd)/$p ;; esac
# pas135: a doua oara (pas108, pas134) s-a dat numele repo-ului in loc de cale.  Nu ghicim
# (refuzul e mai sigur), dar spunem calea exacta, daca exista langa hub.
if [ ! -d "$r/.git" ]; then
  echo "NU: $r nu e un repo git"
  sd=$(cd "$(dirname "$0")" && pwd); rd=$(dirname "$(dirname "$sd")")
  case $r in /*) ;; *) [ -d "$rd/$r/.git" ] && echo "    primul argument e calea completa: $rd/$r" ;; esac
  exit 1
fi
[ -f "$p" ] || { echo "NU: lipseste $p"; exit 1; }
if command -v sha256 >/dev/null 2>&1; then s=$(sha256 -q "$p")
else s=$(sha256sum "$p" | cut -d' ' -f1); fi
if [ "$s" != "$h" ]; then
  echo "NU: amprenta difera — fisierul nu e cel din discutie"
  echo "    asteptata: $h"; echo "    a fisierului: $s"; exit 1
fi
echo "ok   1. amprenta sha256"
# pas181: liniile adaugate, citite inainte de aplicare
sd=$(cd "$(dirname "$0")" && pwd)
[ -s "$sd/injectii.sh" ] || { echo "NU: lipseste $sd/injectii.sh (tiparele) — nu pot citi patch-ul inainte de aplicare"; exit 1; }
. "$sd/injectii.sh"
tm=$(mktemp -d "${TMPDIR:-/tmp}/aplica.XXXXXX") || { echo "NU: nu pot crea un director temporar"; exit 1; }
trap 'rm -rf "$tm"' EXIT
# adaugat: textul liniilor „+” (fara „+”); harta: fisierul si randul din patch, pe acelasi numar de rand
LC_ALL=C awk -v A="$tm/adaugat" -v H="$tm/harta" '
  /^diff --git / { d = 1; next }
  d && /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
  d && /^\+/ { print substr($0, 2) > A; print f "\t" NR > H }' "$p"
if [ -s "$tm/adaugat" ]; then
  inj_invpat "$tm/invpat"
  LC_ALL=C grep -n -F -f "$tm/invpat" "$tm/adaugat" | cut -d: -f1 > "$tm/inv"
  if [ -s "$tm/inv" ]; then
    echo "NU: patch-ul adauga caractere invizibile (zero-width, bidi, BOM sau etichete Unicode) — nimic nu s-a schimbat:"
    while IFS= read -r n; do sed -n "${n}p" "$tm/harta" | awk -F'\t' '{ print "    " $1 ", randul " $2 " din patch" }'; done < "$tm/inv"
    exit 1
  fi
  inj_fraze "$tm/adaugat" | sed 's/.*://' > "$tm/fr"
  inj_amestec "$tm/adaugat" | cut -d: -f2 >> "$tm/fr"
  if [ -s "$tm/fr" ]; then
    echo "ATENTIE: linii adaugate cu fraze adresate masinilor sau litere din alfabete amestecate — citeste-le inainte de commit:"
    sort -n -u "$tm/fr" | while IFS= read -r n; do sed -n "${n}p" "$tm/harta" | awk -F'\t' '{ print "    " $1 ", randul " $2 " din patch" }'; done
  else
    echo "ok   1b. liniile adaugate: niciun caracter invizibil, nicio fraza adresata masinilor"
  fi
else
  echo "ok   1b. patch-ul nu adauga linii"
fi
if [ -n "$(git -C "$r" status --short)" ]; then
  echo "NU: $r are modificari necomise — te opresti si spui:"; git -C "$r" status --short; exit 1
fi
echo "ok   2. arbore curat"
git -C "$r" apply --check "$p" || { echo "NU: patch-ul nu se aplica (git apply --check) — nimic nu s-a schimbat"; exit 1; }
git -C "$r" apply "$p" || { echo "NU: git apply a esuat"; exit 1; }
git -C "$r" add -A
echo "ok   3. aplicat"
asteptat=$(sed -n 's/^# raw: //p' "$p")
efectiv=$(git -C "$r" diff --cached --raw)
if [ -z "$asteptat" ]; then
  echo "ATENTIE: patch-ul nu are randuri „# raw:” — compara de mana cu discutia:"; echo "$efectiv"; exit 1
fi
if [ "$asteptat" != "$efectiv" ]; then
  echo "NU: rezultatul difera de cel asteptat — NU face commit; spune-i lui Claude."
  echo "--- asteptat:"; echo "$asteptat"; echo "--- obtinut:"; echo "$efectiv"
  echo "(inapoi la starea de dinainte: cd $r && git reset -q --hard HEAD)"; exit 1
fi
echo "ok   4. git diff --cached --raw identic cu cel asteptat:"
echo "$efectiv" | sed 's/^/       /'
echo ""
echo "Gata de commit: cd $r && git commit -m \"...\" (mesajul e in discutie)"
