# Bonzátko

Bonzátko je aplikace pro macOS, která hravou formou kontroluje docházku na hodinách. Na projektoru vylosuje jméno studenta s animací kola štěstí. Vyučující mu položí otázku a šipkou zaznamená, jestli je přítomen, nebo nepřítomen. Losování je vážené tak, aby se postupně dostalo na všechny.

Aplikace je v češtině, data ukládá v počítači a výsledky exportuje do Excelu. Word ani Excel ke svému běhu nepotřebuje.

## Co aplikace umí

- **Třídy a studenti.** Třídy lze zakládat, upravovat, archivovat a mazat. Studenty lze přidávat, přejmenovávat a odebírat. Odebraný student se dá kdykoli vrátit i s celou historií.
- **Import studentů** z vloženého textu a ze souborů `.txt`, `.docx`, `.xlsx` a `.csv`. Před uložením se zobrazí náhled a upozornění na duplicity.
- **Hodiny.** Každé setkání třídy je samostatná Hodina. Pokračovat lze jen v poslední Hodině, starší jdou pouze prohlížet.
- **Vážené losování.** Váha studenta je `0,5^n`, kde `n` je počet jeho zaznamenaných vylosování ve všech Hodinách třídy. Každý student může být v jedné Hodině vylosován nejvýše jednou. Nový student začíná na úrovni nejméně losovaného spolužáka.
- **Export do Excelu** při uzavření Hodiny. Soubor obsahuje dva listy:
  - **Hodina:** stav každého studenta, s rozbalovacím seznamem a barevnými řádky;
  - **Souhrn:** součty za všechny Hodiny.
- **Úpravy v Excelu.** Uzavřenou Hodinu lze v Excelu opravit. Při jejím znovuotevření aplikace úpravy ukáže a po potvrzení je převezme.

## Ovládání při losování

| Klávesa | Akce |
|---|---|
| Mezerník | nové losování |
| ↑ | přítomen (jméno zmodrá) |
| ↓ | nepřítomen (jméno zčervená) |
| ← / → | nezaznamenat, student je pro tuto Hodinu vyřazen z osudí |
| Backspace nebo ⌘Z | zpět, vrátí poslední krok |
| F | celá obrazovka a zpět |

Další ovládání na obrazovce Hodiny:
- **Opravit výsledky:** změna stavu kohokoli vylosovaného v této Hodině.
- **Reproduktor:** zapnutí a vypnutí zvuku.
- **Uzavřít Hodinu:** uloží Hodinu do Excelu.

## Jak funguje export

- Soubory se ukládají do `~/Desktop/Bonzátko/<název třídy>/`, například `UDM_Hodina261004.xlsx`. Složku lze změnit v Nastavení (ozubené kolečko nebo ⌘,).
- **Otevřená Hodina nemá soubor.** Mění se jen v aplikaci.
- **Uzavřením Hodiny** (tlačítkem, ukončením aplikace nebo založením nové Hodiny) se soubor vytvoří. Pak ho lze upravovat v Excelu.
- **Znovuotevření Hodiny** načte úpravy z Excelu, ukáže je k potvrzení a soubor přesune do Koše.
- **Založením nové Hodiny** se předchozí Hodina uzavře natrvalo. Její soubor se uzamkne jen pro čtení a aplikace ho už nečte.

## Data

Hlavním zdrojem pravdy je interní úložiště v `~/Library/Application Support/Bonzatko/Classes/`, jeden soubor JSON na třídu. Každá změna se ukládá okamžitě a bezpečně, takže pád aplikace ani výpadek proudu nic nesmaže.

## Sestavení a spuštění

Požadavky: macOS 26 nebo novější, Xcode 26 nebo novější a [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project Bonzatko.xcodeproj -scheme Bonzatko -configuration Release \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Bonzatko-local build
```

Hotová aplikace je ve složce `~/Library/Developer/Xcode/DerivedData/Bonzatko-local/Build/Products/Release/Bonzatko.app`. Přetáhněte ji do složky Aplikace.

> Sestavujte mimo složku Stažené soubory. macOS v ní může blokovat spouštění nově sestavených aplikací, proto příkaz výše ukládá výsledek do `~/Library/Developer`.

Testy:

```bash
xcodebuild -project Bonzatko.xcodeproj -scheme Bonzatko -destination 'platform=macOS' \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/Bonzatko-local test
```

Ikonu kreslí skript `tools/IconGenerator.swift`. Novou sadu velikostí vytvoříte příkazem `swift tools/IconGenerator.swift Bonzatko/Assets.xcassets/AppIcon.appiconset`.

## Knihovny

- [libxlsxwriter](https://github.com/jmcnamara/libxlsxwriter): zápis `.xlsx`, včetně podmíněného formátování a ověření dat.
- [CoreXLSX](https://github.com/CoreOffice/CoreXLSX): čtení `.xlsx` při importu a synchronizaci.
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation): čtení `.docx`.

## Soukromí

Do repozitáře se nikdy nedostávají skutečná jména studentů ani exporty. Testy používají jen smyšlená jména a soubory `.xlsx`, `.docx` a `.csv` jsou v `.gitignore`.

## Licence

[MIT](LICENSE) © 2026 Štefan Švec
