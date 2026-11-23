# lib.awk (pas136) — functiile comune ale garzii norgedan: o singura copie.
#
# Auditul din 10 noiembrie a gasit aceleasi functii scrise de doua-trei ori in
# verifica-site.sh; o corectura facuta intr-o copie nu ajunge singura in celelalte.
# De aici le ia fiecare program awk al garzii:
#   - programele scrise in linie:   awk ... "$LIB_AWK"'program'
#   - programele scrise in fisier:  awk ... -f "$SCRIPT_DIR/lib.awk" -f program.awk
# Garda se opreste daca fisierul lipseste sau e gol (nu tace).
# O functie intra aici doar cand are cel putin doi folositori si acelasi inteles la toti.
# POSIX awk, fara extensii GNU.
#
# pas183: auditul din 23 nov. numarase si norm (3), curat (2), curata (2), cifre (3) ca
# duplicate.  Citite: au acelasi nume, dar fac lucruri diferite (norm = calea unei
# legaturi in [4], textul unui verset in [14], cifrele unui capitol in legaturi.sh; curat si
# curata scot sau nu &nbsp; si spatiile de la capete, dupa nevoia fiecarui loc).  Raman
# fiecare la locul lui: o „unificare” ar schimba ce verifica.  Folosesc biblioteca si
# scripturile din afara garzii (dovezi.sh, legaturi.sh, tablou.sh, subiect.sh), cu acelasi
# „awk ... -f lib.awk” sau "$LIB_AWK".

# dataok(d) — 1 daca d e o data AAAA-LL-ZZ care exista in calendar (pas95)
function dataok(d,   a, l, z, n) { if (d !~ /^20[0-9][0-9]-[01][0-9]-[0-3][0-9]$/) return 0
  a = substr(d, 1, 4) + 0; l = substr(d, 6, 2) + 0; z = substr(d, 9, 2) + 0
  n = (l == 2) ? ((a % 4 == 0 && (a % 100 != 0 || a % 400 == 0)) ? 29 : 28) : (l == 4 || l == 6 || l == 9 || l == 11) ? 30 : 31
  return l >= 1 && l <= 12 && z >= 1 && z <= n }

# litera(c) — 1 daca octetul c tine de un cuvant: litera mica ASCII, cifra sau octet
# dintr-o litera cu diacritice (textul e deja trecut la litere mici)
function litera(c) { return c ~ /[a-z0-9]/ || c > "~" }

# cuvant(t, x) — pozitia la care x apare in t ca expresie intreaga (nu in mijlocul
# unui cuvant); 0 daca nu apare
function cuvant(t, x,   poz, i, st) {
  poz = 1
  while ((i = index(substr(t, poz), x)) > 0) {
    st = poz + i - 1
    if (!(st > 1 && litera(substr(t, st - 1, 1))) && !litera(substr(t, st + length(x), 1))) return st
    poz = st + 1
  }
  return 0
}

# normcifre(t) — separatorul de mii scos dintre cifre („25.000”, „25 000” -> „25000”), ca
# aceeasi cifra sa se recunoasca oricum e scrisa; spatiile nedespartitoare devin spatii
function normcifre(t,   o, i, c, n) {
  gsub(/\302\240|\342\200\257|\342\200\211/, " ", t); o = ""; n = length(t)
  for (i = 1; i <= n; i++) { c = substr(t, i, 1)
    if ((c == "." || c == " ") && i > 1 && substr(t, i - 1, 1) ~ /[0-9]/ && substr(t, i + 1, 3) ~ /^[0-9][0-9][0-9]$/ && substr(t, i + 4, 1) !~ /[0-9]/) continue
    o = o c }
  return o }

# esc(t) — textul pus intr-o pagina HTML: & < > " scrise ca entitati (pas183; dovezi.sh, legaturi.sh)
function esc(t) { gsub(/&/, "\\&amp;", t); gsub(/</, "\\&lt;", t); gsub(/>/, "\\&gt;", t); gsub(/"/, "\\&quot;", t); return t }

# scurteaza(t, n) — t taiat la cel mult n caractere, la granita unui cuvant, cu " ..." (pas183;
# tablou.sh, subiect.sh)
function scurteaza(t, n) { if (length(t) <= n) return t; t = substr(t, 1, n); sub(/ [^ ]*$/, "", t); return t " ..." }
