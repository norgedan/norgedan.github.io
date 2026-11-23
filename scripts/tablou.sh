#!/bin/sh
# tablou.sh — tabloul de bord al site-ului: ce traieste, cat e de proaspat, ce e de facut (pas163).
#
# Pasul D din auditul din 18 nov. 2026.  Scriptul doar CITESTE registrele: nu schimba nicio
# pagina si niciun registru, nu face parte din garda si nu opreste niciun push.
#
#   sh ~/norgedan.github.io/scripts/tablou.sh            tabloul intreg
#   sh ~/norgedan.github.io/scripts/tablou.sh --proba    verifica scriptul pe registre mici, facute de el
#
# Ce arata, in ordine:
#   1. De facut: termenele de reverificare depasite si cele din urmatoarele 30 de zile.
#   2. Actul insusi: afirmatiile care pomenesc o lege, o hotarare, o declaratie, o rezolutie,
#      un tratat... si nu au la sursa nicio dovada primara (P) — regula din pas163: la
#      sursa sta actul insusi (Monitorul Oficial, portalul legislativ, textul oficial),
#      nu presa sau discursurile despre el.
#   3. Subiectele: cate afirmatii (principal + secundar), cand a fost citita ultima sursa,
#      primul termen, evenimentele; starea: viu (sursa citita sau eveniment in ultimele
#      90 de zile), adormit (afirmatii, dar nimic proaspat), doar capitole (nicio afirmatie).
#   4. Datoria, cu progresul ei: randuri „provizoriu”, capitole verificate intreg,
#      afirmatii fara dovezi in surse.tsv, dovezi citite de un om.
#
# Ziua de azi: date +%Y-%m-%d; pentru probe, NORGEDAN_AZI=AAAA-LL-ZZ.
# Registrele: din directorul scriptului; pentru probe, NORGEDAN_TABLOU_DIR.
# POSIX: sh (ksh pe OpenBSD), awk (one-true-awk, fara mktime), sort.  LC_ALL=C.

LC_ALL=C; export LC_ALL
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd) || exit 2
# pas183: scurteaza() vine din biblioteca comuna
LIB_AWK=$(cat "$SCRIPT_DIR/lib.awk" 2>/dev/null)
[ -n "$LIB_AWK" ] || { echo "tablou.sh: lipseste scripts/lib.awk (biblioteca comuna)" >&2; exit 2; }
D=${NORGEDAN_TABLOU_DIR:-$SCRIPT_DIR}
AZI=${NORGEDAN_AZI:-$(date +%Y-%m-%d)}

case "${1:-}" in
  -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
  --proba) PROBA=1 ;;
  "") PROBA=0 ;;
  *) echo "utilizare: sh $0 [--proba]" >&2; exit 2 ;;
esac

# ── proba: registre mici, rezultat cunoscut dinainte ─────────────────
if [ "$PROBA" = 1 ]; then
  P=$(mktemp -d "${TMPDIR:-/tmp}/tablou-proba.XXXXXX") || exit 2
  trap 'rm -rf "$P"' EXIT
  T='	'
  { echo "# test"; echo "s1${T}Unu${T}-${T}-${T}x"; echo "s2${T}Doi${T}-${T}-${T}y"; echo "s3${T}Trei${T}-${T}-${T}z"; } > "$P/subiecte.tsv"
  { echo "# test"
    echo "a1${T}FAPT${T}verificat${T}Legea 1/2020 spune ceva${T}presa${T}2020${T}-${T}2026-01-05"
    echo "a2${T}FAPT${T}verificat${T}o cifra${T}institut${T}2025${T}-${T}2026-02-20"
    echo "a3${T}FAPT${T}verificat${T}Declaratia nr. 3/2022${T}MO${T}2022${T}-${T}-"; } > "$P/afirmatii.tsv"
  { echo "# test"; echo "a1${T}s1${T}s2${T}aprobat"; echo "a2${T}s1${T}-${T}aprobat"; echo "a3${T}s2${T}-${T}propus"; } > "$P/afirmatii-subiecte.tsv"
  { echo "# test"
    echo "a1${T}S${T}https://x${T}2025-06-01${T}claude${T}-"
    echo "a2${T}P${T}https://y${T}2026-01-20${T}bogdan${T}-"
    echo "a3${T}P${T}https://z${T}2025-01-01${T}bogdan${T}-"; } > "$P/surse.tsv"
  { echo "# test"; echo "e1${T}2025-12-25${T}s2${T}-${T}a1${T}x${T}y"; } > "$P/evenimente.tsv"
  { echo "# test"; echo "c1${T}x${T}s1${T}-${T}provizoriu"; echo "c2${T}y${T}s3${T}-${T}citit"; } > "$P/capitole-subiecte.tsv"
  { echo "# test"; echo "c1${T}x${T}t${T}pas1${T}2026-01-01${T}1-1${T}1-1${T}-"; } > "$P/capitole-verificate.tsv"
  NORGEDAN_TABLOU_DIR=$P NORGEDAN_AZI=2026-01-31 sh "$0" > "$P/out" 2>&1 || { echo "PROBA: scriptul a iesit cu eroare"; cat "$P/out"; exit 1; }
  rau=0
  ok_() { if grep -qF -- "$2" "$P/out"; then echo "  ok    $1"; else echo "  GRESIT $1 — lipseste: $2"; rau=1; fi; }
  nu_() { if grep -qF -- "$2" "$P/out"; then echo "  GRESIT $1 — apare: $2"; rau=1; else echo "  ok    $1"; fi; }
  ok_ "termen depasit (a1, 2026-01-05)"            "DEPASIT  2026-01-05  a1"
  ok_ "termen in 30 de zile (a2, 2026-02-20)"     "in 20 z  2026-02-20  a2"
  ok_ "actul insusi: a1 pomeneste o lege, fara P"  "a1  (s1)"
  nu_ "actul insusi: a3 are dovada P"              "a3  (s2)"
  ok_ "s1 viu: sursa citita acum 11 zile"          "s1                       viu"
  ok_ "s2 viu prin eveniment (37 de zile)"         "s2                       viu"
  ok_ "s3 doar capitole"                           "s3                       doar capitole"
  ok_ "afirmatii pe subiect: s1 are 2, ambele principal" "2 (2 pr, 0 sec)"
  ok_ "datoria: 1 din 2 randuri provizoriu"        "capitole-subiecte.tsv: 1 din 2 randuri inca „provizoriu”"
  ok_ "datoria: 1 din 2 capitole verificate"       "capitole verificate intreg: 1 din 2"
  ok_ "propus: 1 din 3"                            "afirmatii cu subiectul inca „propus”: 1 din 3"
  if [ "$rau" = 0 ]; then echo "PROBA: toate verificarile au trecut"; exit 0; fi
  echo "PROBA: ceva nu merge"; exit 1
fi

for f in subiecte.tsv afirmatii.tsv afirmatii-subiecte.tsv surse.tsv evenimente.tsv capitole-subiecte.tsv capitole-verificate.tsv; do
  [ -f "$D/$f" ] || { echo "tablou.sh: lipseste $D/$f" >&2; exit 2; }
done
echo "$AZI" | grep -q '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' || { echo "tablou.sh: ziua „$AZI” nu e AAAA-LL-ZZ" >&2; exit 2; }

awk -F'\t' -v azi="$AZI" -v dir="$D" "$LIB_AWK"'
  function zi(s,   y, m, d, a) {   # zile de la o origine fixa (algoritmul civil, fara mktime)
    if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
    y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; d = substr(s, 9, 2) + 0
    if (m <= 2) { y--; m += 12 }
    a = int(y / 100)
    return int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + d + 2 - a + int(a / 4)
  }
  BEGIN { A = zi(azi) }
  FILENAME == dir "/subiecte.tsv"          { if (!/^#/ && NF >= 2) { sid[++ns] = $1; tit[$1] = $2 } next }
  FILENAME == dir "/afirmatii.tsv"         { if (!/^#/ && NF >= 8) { af[$1] = $4; src[$1] = $5; rv[$1] = $8; ord[++na] = $1 } next }
  FILENAME == dir "/afirmatii-subiecte.tsv" { if (/^#/ || NF < 4) next
                                             pr[$1] = $2; nt++; if ($4 == "propus") npr++
                                             np[$2]++; lista[$2] = lista[$2] " " $1
                                             if ($3 != "-") { k = split($3, b, " "); for (i = 1; i <= k; i++) { nsec[b[i]]++; lista[b[i]] = lista[b[i]] " " $1 } }
                                             next }
  FILENAME == dir "/surse.tsv"             { if (/^#/ || NF < 5) next
                                             are[$1] = 1; if ($2 == "P") areP[$1] = 1; if ($5 != "claude") om[$1] = 1
                                             if ($4 > ult[$1]) ult[$1] = $4
                                             next }
  FILENAME == dir "/evenimente.tsv"        { if (/^#/ || NF < 3) next
                                             if ($2 > ev[$3]) ev[$3] = $2; nev[$3]++
                                             if ($4 != "-") { k = split($4, b, " "); for (i = 1; i <= k; i++) { if ($2 > ev[b[i]]) ev[b[i]] = $2; nev[b[i]]++ } }
                                             next }
  FILENAME == dir "/capitole-subiecte.tsv" { if (/^#/ || NF < 5) next
                                             ncap++; if ($5 == "provizoriu") nprov++
                                             if ($3 != "-") ncs[$3]++
                                             if ($4 != "-") { k = split($4, b, " "); for (i = 1; i <= k; i++) ncs[b[i]]++ }
                                             next }
  FILENAME == dir "/capitole-verificate.tsv" { if (!/^#/ && NF >= 2) nver++; next }
  END {
    print "===================================================="
    print "  TABLOUL SITE-ULUI  ·  " azi
    print "===================================================="
    # 1. de facut
    print ""; print "[1] De facut: termene de reverificare (depasite si in urmatoarele 30 de zile)"
    n1 = 0
    for (i = 1; i <= na; i++) { a = ord[i]; z = zi(rv[a]); if (z < 0) continue
      dz = z - A; if (dz > 30) continue
      lin[++n1] = sprintf("%s\t  %s  %s  %-26s (%s)  %s", rv[a], (dz < 0 ? "DEPASIT" : sprintf("in %2d z", dz)), rv[a], a, (a in pr ? pr[a] : "?"), scurteaza(af[a], 60)) }
    if (n1 == 0) print "  nimic in urmatoarele 30 de zile"
    else { for (i = 2; i <= n1; i++) { x = lin[i]; j = i - 1; while (j >= 1 && lin[j] > x) { lin[j + 1] = lin[j]; j-- } lin[j + 1] = x }
           for (i = 1; i <= n1; i++) { x = lin[i]; sub(/^[^\t]*\t/, "", x); print x } }
    # 2. actul insusi
    print ""; print "[2] Actul insusi: afirmatii care pomenesc un act oficial, fara dovada primara (P) in surse.tsv"
    n2 = 0
    for (i = 1; i <= na; i++) { a = ord[i]; t = tolower(af[a] " " src[a])
      if (t !~ /(legea [0-9]|legea nr|lege nr|legea semnata|hotararea (nr|guvernului|parlamentului|ccr)|hotarare nr|decizia nr|declaratia (politica|nr|parlamentului|comuna)|rezolutia|tratatul|regulamentul|reg\. \(ue\)|ordonanta|monitorul oficial|conventia (europeana|onu|de la))/) continue
      if (a in areP) continue
      n2++; printf "  %s  (%s)  %s\n", a, (a in pr ? pr[a] : "?"), scurteaza(af[a], 70) }
    if (n2 == 0) print "  toate au actul insusi la sursa"
    else print "  " n2 " afirmatii: de cautat actul oficial (Monitorul Oficial, portalul legislativ, textul emitentului) si de pus la sursa"
    # 3. subiectele
    print ""; print "[3] Subiectele: afirmatii, ultima sursa citita, primul termen, evenimente"
    print "  subiect                  stare          afirmatii         ultima sursa  primul termen  evenimente  capitole"
    nviu = nad = ndc = 0
    for (s = 1; s <= ns; s++) { id = sid[s]; k = split(lista[id], b, " "); u = ""; t1 = ""; nP = 0
      for (i = 1; i <= k; i++) { a = b[i]; if (ult[a] > u) u = ult[a]; if (zi(rv[a]) >= 0 && (t1 == "" || rv[a] < t1)) t1 = rv[a] }
      du = (u == "") ? 99999 : A - zi(u); de = (ev[id] == "") ? 99999 : A - zi(ev[id])
      if (k == 0) { st = "doar capitole"; ndc++ } else if (du <= 90 || de <= 90) { st = "viu"; nviu++ } else { st = "adormit"; nad++ }
      printf "  %-24s %-14s %3d (%d pr, %d sec)  %-12s  %-13s  %10d  %8d\n", id, st, k, np[id], nsec[id], (u == "" ? "-" : u), (t1 == "" ? "-" : t1), nev[id], ncs[id] }
    printf "  %d vii, %d adormite, %d doar cu capitole (din %d)\n", nviu, nad, ndc, ns
    # 4. datoria
    print ""; print "[4] Datoria, cu progresul ei"
    nf = 0; nom = 0; for (i = 1; i <= na; i++) { a = ord[i]; if (!(a in are)) nf++; if (a in om) nom++ }
    printf "  capitole-subiecte.tsv: %d din %d randuri inca „provizoriu”\n", nprov, ncap
    printf "  capitole verificate intreg: %d din %d\n", nver, ncap
    printf "  afirmatii cu subiectul inca „propus”: %d din %d\n", npr, nt
    printf "  afirmatii fara dovezi in surse.tsv: %d din %d\n", nf, na
    printf "  afirmatii cu cel putin o dovada citita de un om: %d din %d\n", nom, na
    print ""
    print "  Garda (sh scripts/verifica-site.sh) ramane cea care opreste push-ul; tabloul doar arata."
  }' "$D/subiecte.tsv" "$D/afirmatii.tsv" "$D/afirmatii-subiecte.tsv" "$D/surse.tsv" "$D/evenimente.tsv" "$D/capitole-subiecte.tsv" "$D/capitole-verificate.tsv"
