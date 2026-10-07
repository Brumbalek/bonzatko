# Zadání: aplikace Bonzátko pro macOS

Ahoj, potřebuji od tebe vytvořit nativní aplikaci pro macOS jménem **Bonzátko**. Zadání je podrobně promyšlené; pokud ale narazíš na nejasnost nebo rozpor, zeptej se mě, než začneš hádat.

## Kontext a účel

Učím na vysoké škole a mám několik tříd. Bonzátko slouží ke kontrole docházky hravou formou: na projektoru vylosuje jméno studenta s animací, já mu položím otázku a šipkou zaznamenám, jestli je přítomen, nebo nepřítomen. Losování je vážené tak, aby se postupně dostalo na všechny.

## Technické prostředí

- Počítač: Mac, **macOS Tahoe 26.5.2**. Můžeš použít aktuální API dostupná v této verzi.
- Jazyk a framework: **Swift + SwiftUI**, nativní aplikace s vlastní ikonou v Docku.
- Xcode: myslím, že ho mám. Nejdřív to ověř (`xcode-select -p`, `xcodebuild -version`); pokud chybí, řekni mi a počkej, než ho nainstaluji.
- Word a Excel mám nainstalované, ale aplikace na nich **nesmí záviset**: soubory .docx a .xlsx si čte a zapisuje sama (vhodné knihovny přes Swift Package Manager navrhni a před přidáním mi je krátce zdůvodni; export musí podporovat podmíněné formátování a ověření dat).
- Celé rozhraní je **česky**.
- Aplikace je jen pro mě, ne do App Storu. Na konci mi napiš návod, jak ji sestavit, přesunout do Aplikací a jednorázově povolit v Nastavení → Soukromí a zabezpečení.

## Pojmy

- **Třída**: pojmenovaná skupina studentů (název může být víceslovný s diakritikou, např. „Úvod do marketingu“).
- **Student**: má interní trvalé ID (UUID). Jméno je jen zobrazovaný text; přejmenování ani odebrání nesmí rozbít historii.
- **Hodina**: jedno setkání Třídy, během kterého se losuje.
- **Zaznamenané vylosování**: vylosování označené jako přítomen nebo nepřítomen.

## 1. Data a jejich ukládání

- Hlavním zdrojem pravdy je **interní úložiště** aplikace (Application Support; SwiftData, nebo atomicky zapisované JSON soubory, zvol a zdůvodni).
- **Každá akce** (šipka, oprava, zpět, úprava seznamu) se ukládá okamžitě. Při pádu aplikace nebo vypnutí počítače se nic nesmí ztratit.
- Excel je export, ale lze jím data **opravovat** (viz kapitola 7, synchronizace).

## 2. Třídy a studenti

### Založení a úprava Třídy
- Založení Třídy s libovolným názvem (víceslovný, s diakritikou).
- Při založení se automaticky vytvoří **zkratka pro názvy souborů**, kterou lze ručně upravit:
  - jednoslovný název → to slovo bez diakritiky („Účetnictví“ → `Ucetnictvi`),
  - víceslovný název → první písmena všech slov, velká, bez diakritiky („Úvod do marketingu“ → `UDM`).

### Seznam studentů (po kliknutí na Třídu)
Po kliknutí na Třídu se zobrazí její seznam studentů a přímo v něm:
- **Přidat studenta**: pole pro přímé psaní jména, Enter potvrdí a pole zůstane připravené pro další jméno.
- **Odebrat**: zaškrtnutí jednoho či více studentů v seznamu a potvrzení. Odebraný student se už nelosuje, ale historie mu zůstává a lze ho **vrátit** i s celou historií.
- **Přejmenovat**: dvojklikem na jméno. Historie zůstává.
- **Importovat ze souboru** (hromadné přidání, viz níže).

### Import
- Zdroje: vložený text, .txt, .docx, .xlsx (a .csv).
- Jména se ukládají přesně tak, jak jsou (nerozdělují se na jméno a příjmení).
- **Text / .txt / .docx**: každý neprázdný řádek je jedno jméno; prázdné řádky a nadbytečné mezery se ignorují. Z .docx se bere text odstavců i obsah buněk tabulek.
- **.xlsx / .csv**: zobraz náhled tabulky, kliknutím vyberu sloupec se jmény. Pokud vyberu víc sloupců (jméno a příjmení zvlášť), spojí se mezerou v pořadí výběru. Ostatní sloupce se ignorují.
- Před uložením vždy **náhled nalezených jmen** s možností jména smazat nebo opravit; teprve pak potvrzení.
- **Duplicity**: pokud jméno ve Třídě už existuje, upozorni a nabídni *přeskočit*, nebo *přidat s rozlišením* („Jan Novák (2)“).
- Import do existující Třídy nová jména **přidá**; stávající studenty a jejich historii nemění.

## 3. Hodiny

- Výchozí název Hodiny: `<Plný název Třídy>_HodinaYYMMDD` podle data založení, např. „Úvod do marketingu_Hodina261004“. Druhá Hodina téhož dne: „…_Hodina261004_2“. Název lze editovat.
- **Znovu otevřít** lze jen **poslední** Hodinu Třídy a navázat na její výsledky. Založením nové Hodiny se předchozí definitivně uzavře.
- Starší Hodiny jsou vidět jako uzavřené a jdou **prohlížet** (kdo byl vylosován a s jakým výsledkem), ne měnit.
- **Smazat** lze jen poslední Hodinu (po potvrzení). Předchozí Hodina se tím stane poslední a znovu otevíratelnou.
- **Úvodní obrazovka**: seznam Tříd; u každé tlačítka „Pokračovat v poslední Hodině“ a „Nová Hodina“.

## 4. Losování

### Vážení
- Váha studenta = `0.5 ^ n`, kde `n` je počet jeho **zaznamenaných** vylosování (přítomen + nepřítomen) ve všech Hodinách Třídy.
- Vylosování odkliknuté šipkou doleva/doprava (nezaznamenáno) váhu **nesnižuje**.
- Každý student může být v jedné Hodině vylosován **nejvýše jednou** (bez ohledu na výsledek).
- Odebraní studenti se nelosují.
- **Nový student** přidaný do Třídy, která už má historii, dostane „virtuální“ počet vylosování rovný **nejnižšímu `n` mezi aktivními studenty** v okamžiku přidání. Tento virtuální počet ovlivňuje jen váhu, v exportech se nijak neprojeví.
- Pokud už v osudí nikdo nezbývá, místo animace zobraz: „V této Hodině už byli vylosováni všichni.“

### Ovládání (klávesnice)
| Klávesa | Akce |
|---|---|
| Mezerník | Spustí nové losování |
| Šipka nahoru | Zaznamená **přítomen** |
| Šipka dolů | Zaznamená **nepřítomen** |
| Šipka doleva / doprava | Nezaznamená nic, student je ale pro tuto Hodinu vyřazen z osudí |
| Backspace nebo Cmd+Z | Zpět: vrátí poslední rozhodnutí |
| F | Přepne celou obrazovku a zpět |

Pravidla:
- Dokud u vylosovaného jména nezmáčknu šipku, mezerník nic nespustí; jen se krátce zobrazí nápověda **„Nejdřív označte výsledek“**.
- Během běžící animace se mezerník ignoruje.
- **Zpět** zruší poslední rozhodnutí (vč. vlivu na váhu), znovu zobrazí to jméno a čeká na šipku. Možnost Zpět musí být **viditelná v rozhraní** (tlačítko s popiskem klávesové zkratky).
- Po kliknutí na ikonu v Docku se okno aktivuje a klávesy fungují hned, bez dalšího klikání do okna.

### Obrazovka losování
- Velká plocha přes většinu okna s výrazným jménem. Okno je běžné, lze ho minimalizovat do Docku; klávesou F se přepíná do celé obrazovky pro projektor.
- **Animace**: jména studentů z osudí se rychle střídají a postupně zpomalují (jako kolo štěstí), až se zastaví na vylosovaném. Výchozí délka **2 sekundy**, nastavitelná.
- Vylosované jméno se zobrazí velkým písmem **bez zvláštních efektů** (žádné konfety, zvětšování apod.).
- Po šipce nahoru jméno zbarví **modře**, po šipce dolů **červeně**; po šipce do stran zůstane neutrální.
- **Zvuk**: tiché „cvakání“ během animace a krátký zvuk při zastavení. Jedním tlačítkem vypnutelné.
- Pod jménem se **nezobrazují** žádné statistiky studenta (počty, pravděpodobnost).
- V rohu nenápadné počítadlo „Vylosováno X / Y“ (X = vylosovaní v této Hodině bez ohledu na výsledek, Y = aktivní studenti Třídy).
- Tlačítko **„Opravit výsledky“**: přehled je jinak skrytý; po kliknutí se zobrazí seznam vylosovaných v této Hodině s jejich stavem a u každého lze stav přepnout (přítomen / nepřítomen / nezaznamenáno). Změny se promítnou do vah i exportu.
- Tlačítko **„Exportovat“** pro ruční export.

## 5. Export do Excelu

### Umístění a názvy
- Kořenová složka: **`~/Desktop/Bonzátko/`**, v ní podsložka pro každou Třídu podle jejího plného názvu. Kořenovou složku lze změnit v nastavení.
- Název souboru = název Hodiny, v němž se plný název Třídy nahradí **zkratkou** Třídy, např. `UDM_Hodina261004.xlsx`. Znaky nepovolené v názvech souborů nahraď. Při přejmenování Hodiny se soubor přejmenuje. Cestu k souboru si aplikace pamatuje interně.

### List 1 „Hodina“
- Všichni aktivní studenti Třídy, abecedně (české řazení).
- Sloupce: **Jméno**, **Stav** (`přítomen` / `nepřítomen` / prázdné) a **skrytý sloupec s ID studenta** (pro spolehlivé zpětné načtení).
- Sloupec Stav má rozbalovací seznam (ověření dat) s povolenými hodnotami.
- Podbarvení řádku řídí **podmíněné formátování podle sloupce Stav**: přítomen = modrá, nepřítomen = červená, prázdné = bez podbarvení. Když Stav v Excelu přepíšu, barva se změní sama.

### List 2 „Souhrn“
- **Všichni studenti Třídy**, abecedně, s výsledky za všechny dosavadní Hodiny včetně aktuální.
- Sloupce: **Jméno**, **Přítomnosti**, **Nepřítomnosti**, **Celkem zaznamenán**, **Poznámka**.
- Studenti dosud nezaznamenaní mají nuly a v Poznámce „Zatím nevylosován“.
- Odebraní studenti s historií zůstávají v souhrnu s poznámkou „odebrán“.
- Jen součty, žádné rozpisy po Hodinách.

### Kdy se exportuje
- Po kliknutí na „Exportovat“.
- Automaticky při **zavření aplikace** (rozpracovaná Hodina).
- Automaticky při **založení nové Hodiny** (finální export předchozí Hodiny).
- Opakovaný export stejné Hodiny soubor **přepíše**.
- Pokud soubor nejde přepsat (je otevřený v Excelu; hlídej i zámkový soubor `~$…`), upozorni mě a export zopakuj, jakmile soubor zavřu. Data jsou mezitím v bezpečí v interním úložišti.

## 6. Synchronizace s upraveným Excelem

- Při **založení nové Hodiny** aplikace načte export předchozí (poslední) Hodiny a porovná sloupec Stav v Listu 1 (párování podle skrytého ID, záložně podle jména) se svými daty.
- Pokud najde rozdíly (moje ruční úpravy), **zobrazí je** (kdo, původní stav → nový stav) a po potvrzení je převezme do interních dat, tedy i do vah a souhrnů.
- List 2 se zpětně nenačítá, vždy se počítá z dat.
- Pokud soubor chybí nebo je nečitelný, upozorni a pokračuj s interními daty.
- Po založení nové Hodiny už změny v exportu předchozí Hodiny nemají vliv.

## 7. Nastavení
- Kořenová složka exportů (výchozí `~/Desktop/Bonzátko/`).
- Délka animace (výchozí 2 s).
- Zvuk zapnuto/vypnuto.

## 8. Ikona
Navrhni vlastní **originální** ikonu aplikace v plné sadě velikostí pro macOS: motiv **kola štěstí**, případně doplněný stylizovanou sojkou (obecný pták, nesmí připomínat symbol sojky reprodrozdové z Hunger Games ani jiný existující logotyp). Ukaž mi návrh, než ho zapracuješ.

## 9. GitHub
- Projekt veď od začátku jako git repozitář; na konci ho chci dát na svůj GitHub.
- README v češtině: co aplikace dělá, ovládání, sestavení a spuštění.
- `.gitignore` pro Xcode/Swift.
- Licenci se mě zeptej.
- **Do repozitáře se nikdy nesmí dostat skutečná jména studentů ani exporty.** V testech a ukázkách používej jen smyšlená jména.

## Postup práce
1. Ověř prostředí (Xcode) a navrhni mi architekturu, datový model a knihovny. Počkej na můj souhlas.
2. Stav aplikaci po fázích, které lze průběžně spustit a vyzkoušet:
   1. Třídy, studenti, import.
   2. Hodiny a ukládání.
   3. Losování, vážení, ovládání, animace.
   4. Export do Excelu a synchronizace.
   5. Nastavení, zvuk, ikona, README.
3. Napiš jednotkové testy minimálně pro: vážené losování (vč. virtuálního počtu u nových studentů a pravidla „max. jednou za Hodinu“), tvorbu zkratek a názvů souborů, parsování importů, export a zpětné načtení Excelu (round-trip).
4. Po každé fázi mi stručně řekni, co a jak vyzkoušet.
