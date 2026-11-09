#!/bin/sh
# mostra.sh (pas134) — ochi de om pe dovezi.  Gravitatea 2 din auditul din 8 noiembrie.
#
# Garda verifica forma dovezilor (nivel, adresa, data, citat), nu si daca pagina sursei
# spune cu adevarat ce scrie in citat.  Asta o poate vedea doar un om care o deschide.
# Cele mai multe dovezi le-a citit doar Claude; aici le citeste si Bogdan, cate putine
# o data, alese la intamplare.
#
#   sh scripts/verifica-site.sh --mostra [N]           N afirmatii (implicit 4) citite
#        pana acum doar de Claude, FAPT intai.  Afirmatia si adresele, FARA citatul lui
#        Claude: cauti singur in pagina ce o sustine, ca sa nu confirmi doar ce ti s-a
#        aratat.  Aceeasi zi = aceeasi alegere (samanta e data); a doua zi, alta.
#   sh scripts/verifica-site.sh --mostra [N] --citat   la fel, cu citatele, ca sa compari.
#   sh scripts/verifica-site.sh --confirma <id> <url>  sursa sustine afirmatia si citatul e
#        in pagina: adauga in surse.tsv, dupa randul lui Claude, acelasi rand cu cititorul
#        tau si data de azi, apoi rescrie dovezi.html.  Verificarile se fac INAINTE de
#        scriere; daca una pica, surse.tsv ramane neatinsa.
#   Daca sursa NU sustine afirmatia: nu confirma nimic; spune-i lui Claude — intra la
#   „Grav” in punctele slabe (regula 24) si se repara la pasul urmator.
#
# Cititorul: NORGEDAN_CITITOR (implicit bogdan); litere mici; niciodata „claude”.
# Iesire: 0 = bine, 1 = verificare picata (nimic scris), 2 = utilizare gresita.
# POSIX: sh, awk, sort, date, mv.  Fara extensii GNU.
LC_ALL=C; export LC_ALL
SD=$(cd "$(dirname "$0")" && pwd)
SURSE="$SD/surse.tsv"; AFIRMATII="$SD/afirmatii.tsv"; VSH="$SD/verifica-site.sh"
CITITOR=${NORGEDAN_CITITOR:-bogdan}
AZI=$(date +%Y-%m-%d)
TAB=$(printf '\t')
W=$(mktemp -d /tmp/mostra.XXXXXX) || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 1' INT TERM HUP

uz() { echo "utilizare: sh $VSH --mostra [N] [--citat]  |  --confirma <id> <url>" >&2; exit 2; }
[ -f "$SURSE" ] && [ -f "$AFIRMATII" ] || { echo "PROBLEMA lipseste scripts/surse.tsv sau scripts/afirmatii.tsv" >&2; exit 1; }

MOD=${1:-}; [ $# -gt 0 ] && shift
case $MOD in
# ────────────────────────────────────────────────────────────────────
--mostra)
  N=4; CITAT=0
  for a in "$@"; do
    case $a in
      --citat) CITAT=1 ;;
      *[!0-9]*|'') uz ;;
      *) N=$a ;;
    esac
  done
  [ "$N" -ge 1 ] 2>/dev/null || uz
  # samanta: ziua (NORGEDAN_ZI doar pentru teste — schimba alegerea, nu si datele scrise)
  ZI=${NORGEDAN_ZI:-$AZI}
  # candidatii: afirmatii verificate, cu surse, fara niciun cititor om
  # cheia: FAPT intai (0), apoi restul (1); in grup, un amestec nelinear al (zi, id)
  awk -F'\t' -v AF="$AFIRMATII" -v ZI="$ZI" -v STAT="$W/stat" '
    BEGIN { A = " !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
            while ((getline l < AF) > 0) { if (l ~ /^#/) continue; split(l, x, "\t"); et[x[1]] = x[2]; st[x[1]] = x[3] } }
    function amesteca(s,   h, i) { h = 1
      for (i = 1; i <= length(s); i++) h = (h * h + 31 * h + index(A, substr(s, i, 1)) + 1) % 65521
      return h }
    /^#/ || NF != 6 { next }
    { are[$1] = 1; if ($5 != "claude") om[$1] = 1 }
    END { for (i in are) { T++; if (i in om) O++
            if ((i in om) || st[i] != "verificat") continue
            C++; printf "%d\t%05d\t%s\n", (et[i] == "FAPT" ? 0 : 1), amesteca(ZI ":" i ":" ZI), i }
          printf "STAT\t%d\t%d\t%d\n", T, O, C > STAT }' "$SURSE" | sort -t "$TAB" -k1,1n -k2,2n -k3,3 > "$W/cand"
  set -- $(cut -f2- "$W/stat" | tr '\t' ' ')
  T=$1; O=$2; C=$3
  if [ "$C" -eq 0 ]; then echo "  Toate cele $T afirmatii cu dovezi au fost citite si de un om. Nimic de aratat."; exit 0; fi
  [ "$N" -gt "$C" ] && N=$C
  head -n "$N" "$W/cand" | cut -f3 > "$W/ales"
  echo ""
  echo "  Mostra din $AZI: $N din $C afirmatii citite pana acum doar de Claude (citite si de un om: $O din $T)."
  if [ "$CITAT" = 0 ]; then
    echo "  Deschide fiecare adresa si cauta TU ce sustine afirmatia.  Citatele lui Claude sunt ascunse;"
    echo "  le vezi dupa aceea, ca sa compari:  sh $VSH --mostra $N --citat"
  fi
  awk -F'\t' -v AF="$AFIRMATII" -v AL="$W/ales" -v CITAT="$CITAT" -v VSH="$VSH" '
    BEGIN { while ((getline l < AF) > 0) { if (l ~ /^#/) continue; split(l, x, "\t"); et[x[1]] = x[2]; tx[x[1]] = x[4] }
            while ((getline l < AL) > 0) { k++; ord[k] = l; ales[l] = k } }
    /^#/ || NF != 6 || !($1 in ales) { next }
    { n[$1]++; u[$1, n[$1]] = $3; nv[$1, n[$1]] = $2; ct[$1, n[$1]] = $6 }
    END { for (j = 1; j <= k; j++) { i = ord[j]
            printf "\n  %d. %s  (%s)\n     Afirmatia: %s\n     Pe site:   https://norgedan.github.io/dovezi.html#%s\n     Surse:\n", j, i, et[i], tx[i], i
            for (z = 1; z <= n[i]; z++) {
              if (!((i, u[i, z]) in vazut)) { vazut[i, u[i, z]] = 1; printf "       %s %s\n", nv[i, z], u[i, z] }
              if (CITAT == 1) printf "           %s\n", (ct[i, z] == "-" ? "(fara citat exact)" : ct[i, z])
            }
            printf "     Daca sursa sustine afirmatia (pentru fiecare adresa citita):\n"
            for (z = 1; z <= n[i]; z++) if (!((i, u[i, z]) in dat)) { dat[i, u[i, z]] = 1
              printf "       sh %s --confirma %s \047%s\047\n", VSH, i, u[i, z] } } }' "$SURSE"
  echo ""
  echo "  Daca o sursa NU sustine afirmatia: nu confirma; spune-i lui Claude (regula 24, „Grav”)."
  exit 0 ;;
# ────────────────────────────────────────────────────────────────────
--confirma)
  [ $# -eq 2 ] || uz
  ID=$1; URL=$2
  case $CITITOR in claude) echo "PROBLEMA cititorul nu poate fi „claude” — confirmarea e ochiul omului" >&2; exit 2 ;; esac
  printf '%s\n' "$CITITOR" | grep -q '^[a-z][a-z-]*$' || { echo "PROBLEMA cititorul „$CITITOR” — un nume, litere mici" >&2; exit 2; }
  printf '%s\n' "$ID" | grep -q '^[a-z0-9-]*$' || { echo "PROBLEMA id „$ID” — litere mici, cifre si -" >&2; exit 1; }
  printf '%s\n' "$AZI" | grep -q '^20[0-9][0-9]-[01][0-9]-[0-3][0-9]$' || { echo "PROBLEMA data de azi „$AZI” nu e AAAA-LL-ZZ" >&2; exit 1; }
  tail -c 1 "$SURSE" | od -An -c | grep -q '\\n' || { echo "PROBLEMA surse.tsv nu se termina cu rand nou — nimic scris" >&2; exit 1; }
  # Toate verificarile, apoi scrierea intr-un fisier nou; surse.tsv se inlocuieste doar la sfarsit.
  awk -F'\t' -v OFS='\t' -v AF="$AFIRMATII" -v ID="$ID" -v URL="$URL" -v CIN="$CITITOR" -v AZI="$AZI" -v OUT="$W/nou" '
    BEGIN { while ((getline l < AF) > 0) { if (l ~ /^#/) continue; split(l, x, "\t"); if (x[1] == ID) { af = 1; stf = x[3] } } }
    { r[NR] = $0; f[NR] = NF }
    !/^#/ && NF == 6 && $1 == ID { ult = NR
      if ($3 == URL && $5 == "claude") { k++; cl[k] = NR }
      if ($3 == URL && $5 == CIN) deja = 1 }
    END {
      if (!af) { print "PROBLEMA \"" ID "\" nu e in afirmatii.tsv"; exit 1 }
      if (stf != "verificat") { print "PROBLEMA \"" ID "\" are starea \"" stf "\", nu verificat"; exit 1 }
      if (deja) { print "PROBLEMA " CIN " a confirmat deja aceasta adresa pentru \"" ID "\" — nimic de adaugat"; exit 1 }
      if (k == 0) { print "PROBLEMA adresa nu e in surse.tsv pentru \"" ID "\" ca sursa citita de Claude — copiaz-o exact din --mostra"; exit 1 }
      for (i = 1; i <= NR; i++) { print r[i] > OUT
        if (i == ult) for (j = 1; j <= k; j++) { split(r[cl[j]], c, "\t"); print c[1], c[2], c[3], AZI, CIN, c[6] > OUT } }
      close(OUT); printf "ADAUGAT\t%d\t%d\n", k, NR }' "$SURSE" > "$W/rez"
  if [ $? -ne 0 ]; then cat "$W/rez" >&2; echo "  surse.tsv a ramas neatinsa." >&2; exit 1; fi
  set -- $(cut -f2- "$W/rez" | tr '\t' ' ')
  K=$1; VECHI=$2
  NOU=$(wc -l < "$W/nou" | tr -d ' ')
  [ "$NOU" -eq $((VECHI + K)) ] || { echo "PROBLEMA fisierul nou are $NOU randuri, asteptat $((VECHI + K)) — nimic scris" >&2; exit 1; }
  cp "$W/nou" "$SURSE.mostra.$$" && mv "$SURSE.mostra.$$" "$SURSE" || { rm -f "$SURSE.mostra.$$"; echo "PROBLEMA surse.tsv nu a putut fi inlocuita" >&2; exit 1; }
  echo "  Adaugat in surse.tsv: $K rand(uri) pentru $ID, citit(e) de $CITITOR pe $AZI."
  if sh "$SD/dovezi.sh" --scrie > "$W/dov" 2>&1; then echo "  $(cat "$W/dov")"
  else echo "PROBLEMA dovezi.sh s-a oprit: $(head -1 "$W/dov") — ruleaza: sh $SD/dovezi.sh --scrie" >&2; exit 1; fi
  echo "  Urmeaza: garda (sh $VSH), apoi commit cu scripts/surse.tsv si dovezi.html."
  exit 0 ;;
*) uz ;;
esac
