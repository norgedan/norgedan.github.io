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
# Commit-ul si push-ul raman ale lui Bogdan: scriptul doar pregateste si spune ce a vazut.
# Portabil POSIX: OpenBSD (sha256 -q) si Linux (sha256sum).
[ $# -eq 3 ] || { echo "utilizare: sh $0 <repo> <patch> <sha256>" >&2; exit 2; }
r=$1; p=$2; h=$3
case $p in /*) ;; *) p=$(pwd)/$p ;; esac
[ -d "$r/.git" ] || { echo "NU: $r nu e un repo git"; exit 1; }
[ -f "$p" ] || { echo "NU: lipseste $p"; exit 1; }
if command -v sha256 >/dev/null 2>&1; then s=$(sha256 -q "$p")
else s=$(sha256sum "$p" | cut -d' ' -f1); fi
if [ "$s" != "$h" ]; then
  echo "NU: amprenta difera — fisierul nu e cel din discutie"
  echo "    asteptata: $h"; echo "    a fisierului: $s"; exit 1
fi
echo "ok   1. amprenta sha256"
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
