# harta.awk — perechea RO-NO a capitolelor norgedan (pas120).
# Folosit de verifica-site.sh ([18], [19]) si de legaturi.sh.
# Intrare: randurile din capitole.awk (doc TAB lang TAB poz TAB ancora TAB titlu),
#          RO si NO, documentele in ordinea manifestului.  Rulat cu  awk -F'\t'.
# In corpus si corpus2 ancorele NO sunt traduse (minte-inima / hjerte), deci perechea
# se face pe pozitie.  Capitolele doar-NO (rolul Norvegiei, ancora norge...) se sar.
# Iesire:
#   MAP        TAB doc TAB poz-RO TAB poz-NO TAB ancora-NO TAB ancora-RO
#   DOARNO     TAB doc TAB poz-NO TAB ancora-NO
#   NEPOTRIVIT TAB doc TAB capitole-RO TAB capitole-NO   (nu se pot pune fata in fata)
{ k = $1 "\t" $2; n[k]++; a[k "\t" n[k]] = $4; if ($2 == "ro" && !($1 in v)) { v[$1] = 1; ord[++nd] = $1 } }
  END { for (q = 1; q <= nd; q++) { d = ord[q]; nr = n[d "\tro"]; nn = n[d "\tno"]; extra = nn - nr; j = 0
          for (i = 1; i <= nn; i++) { an = a[d "\tno\t" i]
            if (extra > 0 && an ~ /^norge/) { print "DOARNO\t" d "\t" i "\t" an; extra--; continue }
            j++; if (j <= nr) print "MAP\t" d "\t" j "\t" i "\t" an "\t" a[d "\tro\t" j] }
          if (j != nr) print "NEPOTRIVIT\t" d "\t" nr "\t" nn } }
