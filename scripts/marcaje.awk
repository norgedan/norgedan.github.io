# marcaje.awk — cititorul unic al marcajelor de afirmatie (pas196, punctul (c) din regula 38).
#
# Un marcaj e forma exacta <span data-afirmatie="ID"> ... pana la </span>-ul pereche,
# in afara comentariilor HTML (<!-- ... -->).  Orice alt tag care poarta data-afirmatie=
# (alt atribut, alte ghilimele, alt element) nu e marcaj: e doar numarat in MK_ALTE —
# garda [13] il blocheaza separat.  Un marcaj intr-un marcaj nu e citit separat: cel
# din afara primeste MK_IMB = 1 (garda [13]: span in span = PROBLEMA).
#
# Folosire:  awk -f scripts/marcaje.awk -f program.awk pagina.html
#   In program, cu toata pagina intr-un singur sir s (RS = "\001"):  marcaje(s)
#   umple, pentru k = 1 .. MK_N, in ordinea din pagina:
#     MK_ID[k]   id-ul afirmatiei
#     MK_A[k]    pozitia lui „<span data-afirmatie=” in s
#     MK_B[k]    pozitia primului caracter din interiorul marcajului
#     MK_E[k]    pozitia </span>-ului pereche (0 = marcajul nu se inchide)
#     MK_IMB[k]  1 daca inauntru e un alt <span>
#     MK_ANC[k]  id-ul ultimului <section id="..."> sau <h2 id="..."> dinaintea marcajului
#   Interiorul:  substr(s, MK_B[k], MK_E[k] - MK_B[k])  (cu tag-urile lui, daca are).
# Pozitiile sunt in octeti (LC_ALL=C), in sirul intreg, deci un program poate rescrie pagina.
# Pagina se imparte o singura data la „<” (lectia din pas70: fara copii ale restului la
# fiecare tag).  POSIX awk: one-true-awk (OpenBSD), mawk, gawk, busybox.
# MK_ANC: regula veche din dovezi.sh, pastrata ca sa nu schimbe nimic; capitolul se ia, la
# index, din capitole.awk (pasul urmator din (c)).

function marcaje(s,    n, k, p, part, j, tag, M, LM, id, q, desch, d, com, anc) {
  MK_N = 0; MK_ALTE = 0
  M = "<span data-afirmatie=\""; LM = length(M)
  n = split(s, part, "<")
  p = length(part[1]) + 1          # pozitia „<”-ului care incepe part[2]
  desch = 0; d = 0; com = 0; anc = ""
  for (k = 2; k <= n; k++) {
    if (k > 2) p += length(part[k - 1]) + 1
    if (com) { if (index(part[k], "-->")) com = 0; continue }
    if (substr(part[k], 1, 3) == "!--") {
      if (!index(substr(part[k], 4), "-->")) com = 1
      continue
    }
    j = index(part[k], ">"); if (!j) continue
    tag = "<" substr(part[k], 1, j)
    if (desch) {
      if (tag ~ /^<span[ >]/) { d++; MK_IMB[desch] = 1 }
      else if (tag ~ /^<\/span>/) { d--; if (d == 0) { MK_E[desch] = p; desch = 0 } }
      continue
    }
    if (tag ~ /^<(section|h2)[ >]/ && match(tag, /id="[^"]*"/)) anc = substr(tag, RSTART + 4, RLENGTH - 5)
    if (substr(tag, 1, LM) == M) {
      id = substr(tag, LM + 1); q = index(id, "\"")
      if (q > 1 && substr(id, q) == "\">") {
        MK_N++; MK_ID[MK_N] = substr(id, 1, q - 1); MK_A[MK_N] = p; MK_B[MK_N] = p + length(tag)
        MK_E[MK_N] = 0; MK_IMB[MK_N] = 0; MK_ANC[MK_N] = anc
        desch = MK_N; d = 1
        continue
      }
    }
    if (index(tag, "data-afirmatie=")) MK_ALTE++
  }
}
