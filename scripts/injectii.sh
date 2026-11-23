# injectii.sh (pas181) - tiparele comune pentru caracterele invizibile, frazele adresate
# masinilor si cuvintele cu alfabete amestecate.  O singura copie, incarcata cu "." de
# verifica-site.sh ([22] si --surse) si de aplica.sh (liniile adaugate de un patch, inainte
# de aplicare).  Singur nu verifica nimic: doar defineste functiile de mai jos.
# Sta sub sigiliu (scripts/*.sh): o lista slabita pe ascuns se vede la sigilare.
# Fisierul e numai ASCII: literele romanesti si norvegiene sunt scrise ca octeti (\304\203 = a cu
# caciula), ca sa se citeasca la fel in orice terminal.
# Aceeasi lista de fraze, scrisa ca regex Python, e in citeste-sursa.py (INJ): cine o schimba
# pe una o schimba si pe cealalta.
#
#   inj_invpat <fisier>       scrie tiparele caracterelor invizibile, unul pe rand (grep -F -f)
#   inj_fraze <fisier...>     "fisier:rand" pentru fiecare rand cu o fraza adresata masinilor
#   inj_amestec <fisier...>   "fisier:rand:bucata" unde o litera latina sta lipita de una
#                             chirilica sau greceasca (un "a" chirilic intr-un cuvant latin
#                             arata la fel, dar nu mai e gasit de [7] si [13])
# POSIX sh si awk; tiparele lucreaza pe octeti (LC_ALL=C), ca in restul garzii.

inj_invpat() {
  : > "$1" || return 1
  # zero-width si marcajele de directie (U+200B-200F), controlul bidi (U+202A-202E)
  for c in 213 214 215 216 217; do printf "\\342\\200\\$c\n" >> "$1"; done
  for c in 252 253 254 255 256; do printf "\\342\\200\\$c\n" >> "$1"; done
  # U+2060-2064, izolarile bidi U+2066-2069
  for c in 240 241 242 243 244 246 247 250 251; do printf "\\342\\201\\$c\n" >> "$1"; done
  # BOM (U+FEFF)
  printf '\357\273\277\n' >> "$1"
  # pas91: separatorul de rand si de paragraf (U+2028, U+2029), CGJ (U+034F), U+180E si
  # umplutura Hangul (U+115F, U+1160, U+3164, U+FFA0) - toate se vad ca nimic
  for x in '\342\200\250' '\342\200\251' '\315\217' '\341\240\216' '\341\205\237' '\341\205\240' '\343\205\244' '\357\276\240'; do
    printf "$x\n" >> "$1"
  done
  # etichetele Unicode (U+E0000-E007F)
  for x in 0 1 2 3 4 5 6 7; do for y in 0 1 2 3 4 5 6 7; do
    printf "\\363\\240\\200\\2$x$y\n" >> "$1"; printf "\\363\\240\\201\\2$x$y\n" >> "$1"
  done; done
}

# Frazele: textul trecut la litere mici; literele mari cu diacritice (A, T, S cu semne, A cu cerc) nu le
# micsoreaza tolower, deci sunt scrise si ele.  ([^a-z]|$) = sfarsit de cuvant ("ai", nu "aid").
inj_fraze() {
  LC_ALL=C awk '{ t = tolower($0) }
  t ~ /(ignore|forget) (all |any |the |your )?(previous|prior|above|earlier) (instructions|prompts?|rules)/ ||
  t ~ /disregard (all |any |the |your )?(previous|prior|above|earlier)/ ||
  t ~ /new instructions[ \t]*:|system prompt|<[\/]?system>|[[][\/]?inst[]]|<[|]im_(start|end)[|]>|<[|]endoftext[|]>|<<[\/]?sys>>/ ||
  t ~ /^[ \t]*#+[ \t]*(instruction|instructions|response)[ \t]*:?[ \t]*$/ ||
  t ~ /you are (now )?(chatgpt|claude|gemini|copilot|an ai([^a-z]|$)|a language model|a large language model|an assistant)|as an ai language model/ ||
  t ~ /if you are an? (ai([^a-z]|$)|llm([^a-z]|$)|language model|large language model|assistant|chatbot)/ ||
  t ~ /(dear|attention|note to|instructions? (for|to)) (ai([^a-z]|$)|llm([^a-z]|$)|ai assistants?|language models?|chatbots?|claude|chatgpt)/ ||
  t ~ /do not (tell|inform|reveal to|mention (this )?to) the user/ ||
  t ~ /(ignor|uit)(\304\203|\304\202|a) (toate )?instruc(\310\233|\305\243|\310\232|\305\242|t)iunile|instruc(\310\233|\305\243|\310\232|\305\242|t)iuni noi[ \t]*:/ ||
  t ~ /dac(\304\203|\304\202|a) e(\310\231|\305\237|\310\230|\305\236|s)ti (un |o )?(ai([^a-z]|$)|asistent|model de limbaj|inteligen(\310\233|\305\243|\310\232|\305\242|t)(\304\203|\304\202|a) artificial(\304\203|\304\202|a))/ ||
  t ~ /nu[- ]i spune utilizatorului/ ||
  t ~ /(ignorer|glem) (alle )?tidligere instruksjoner|nye instruksjoner[ \t]*:|ikke fortell brukeren/ ||
  t ~ /hvis du er en (ai([^a-z]|$)|ki([^a-z]|$)|spr(\303\245|\303\205|a)kmodell|assistent)/ { print FILENAME ":" FNR }' "$@"
}

# Litera latina: ASCII sau U+00C0-U+027F (octetul de inceput \303-\311).  Litera chirilica sau
# greceasca: U+0370-U+04FF (\315\260-\315\277, apoi \316-\323).  Semnele diacritice combinate
# (U+0300-U+036F) nu intra: "a" + caciula combinata ramane un cuvant latin.
inj_amestec() {
  LC_ALL=C awk '{
    if (match($0, /([A-Za-z]|[\303-\311][\200-\277])(\315[\260-\277]|[\316-\323][\200-\277])/) ||
        match($0, /(\315[\260-\277]|[\316-\323][\200-\277])([A-Za-z]|[\303-\311][\200-\277])/)) {
      s = RSTART > 12 ? RSTART - 12 : 1
      b = substr($0, s, RLENGTH + 24)
      sub(/^[\200-\277]+/, "", b); sub(/[\300-\377][\200-\277]*$/, "", b)
      print FILENAME ":" FNR ":" b
    } }' "$@"
}
