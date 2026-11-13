# Copy8

Cronologia degli appunti per macOS. Una scorciatoia (di default ⇧⌘V) apre una finestra con tutto quello
che hai copiato negli ultimi giorni, dal più recente al più vecchio, con ricerca full text.

## Compilare e installare

Servono macOS 14 o successivo e gli strumenti da riga di comando di Xcode (`xcode-select --install`).

```bash
scripts/build-app.sh             # crea build/Copy8.app
scripts/build-app.sh --install   # la copia anche in /Applications
```

L'app vive nella barra dei menu e non compare nel Dock. Per riaprire le impostazioni: icona nella barra
dei menu › Impostazioni…, oppure ⌘, con la finestra aperta.

## Permesso Accessibilità

Per incollare direttamente nell'app attiva Copy8 simula ⌘V, e macOS lo consente solo con il permesso
in Impostazioni di Sistema › Privacy e sicurezza › Accessibilità. Senza permesso l'elemento viene copiato
negli appunti e basta premere ⌘V.

La build è firmata ad-hoc: dopo ogni ricompilazione macOS la considera un'app nuova. Se l'incolla smette di
funzionare, togli Copy8 dall'elenco Accessibilità con il tasto − e aggiungilo di nuovo.

## Nella finestra

| Tasti | Azione |
|---|---|
| ↑ ↓, Pagina su/giù | Scegli l'elemento |
| ↩ | Incolla nell'app attiva |
| ⌥↩ | Incolla come testo semplice |
| ⌘1 … ⌘9 | Incolla l'elemento in quella posizione |
| ⌘C | Copia senza incollare (se nel campo di ricerca non c'è testo selezionato) |
| ⌘⌫ | Elimina l'elemento |
| ⌘, | Impostazioni |
| esc | Svuota la ricerca, poi chiude |

La ricerca ignora maiuscole e accenti e richiede tutte le parole scritte, in qualunque punto del testo o
nel nome dell'app di origine. Clic destro su una riga per incollare, copiare o eliminare.

## Impostazioni

- **Conserva gli elementi per**: numero di giorni (1–365, default 7). Quello che è più vecchio viene eliminato.
- **Incolla direttamente nell'app attiva**: se spento, Copy8 copia soltanto.
- **Apri la cronologia**: clicca e premi la nuova combinazione (serve ⌘, ⌃ o ⌥).
- **Avvia al login**.
- **Tema**: Sistema, Chiaro, Scuro.
- **Mostra anteprima**: pannello di destra con il contenuto completo e i dettagli.
- **Effetto vetro** e **Intensità** (1–100), con anteprima dal vivo. A 1 la superficie è quasi piena, a 100
  la finestra è vetro lucido e molto trasparente. La sfocatura resta piena fino a circa 40 e a 100 ne resta
  circa un terzo; la tinta della superficie scende dal 94% a circa il 24%; da metà scala in su compaiono i
  riflessi (filo di luce sul bordo, riflesso in alto, bordo inferiore più scuro) e un alone dietro il testo
  che lo tiene leggibile su qualsiasi sfondo.
- **Ignora password e contenuti riservati**: salta quello che i password manager marcano come riservato.
- **Cancella cronologia…**: si può annullare finché la finestra delle impostazioni è aperta.

## Dati

Tutto resta sul Mac, in `~/Library/Application Support/Copy8/`: `history.sqlite` per testi, link e
percorsi, la cartella `Images/` per le immagini. Copy8 riconosce testo, link, codice, colori (`#RRGGBB`,
`rgb()`), immagini e file. Il testo formattato (RTF, HTML) viene conservato e incollato così com'era.
Copy8 ignora un testo più lungo di un milione di caratteri e un'immagine più grande di 40 MB.

## Struttura

| File | Ruolo |
|---|---|
| `AppDelegate.swift` | Avvio, menu, collegamenti tra le parti |
| `ClipboardWatcher.swift` | Controlla gli appunti ogni 0,4 s e riconosce il tipo di contenuto |
| `Store.swift`, `History.swift` | Archivio SQLite e cronologia in memoria |
| `PanelController.swift`, `PanelModel.swift`, `PanelView.swift` | La finestra: tastiera, ricerca, elenco, anteprima |
| `Paster.swift` | Scrive negli appunti e simula ⌘V |
| `HotKey.swift` | Scorciatoia globale (Carbon, non richiede permessi) |
| `SettingsView.swift`, `Settings.swift` | Impostazioni e loro salvataggio |
| `Theme.swift` | Token del design system, chiaro e scuro |
| `Toast.swift` | Conferma dopo l'incolla |

La finestra viene creata e disegnata una volta all'avvio e poi solo mostrata, così si apre al frame
successivo alla scorciatoia.
