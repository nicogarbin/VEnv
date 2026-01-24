# VEnv

VEnv è un'applicazione mobile sviluppata con Flutter. Questo documento fornisce le istruzioni dettagliate per configurare l'ambiente di sviluppo, eseguire l'app su un emulatore e installarla su un dispositivo fisico Android.

---

## Prerequisiti

Prima di iniziare, assicurati di avere installato i seguenti strumenti:

* **Flutter SDK:** [Scarica qui](https://docs.flutter.dev/get-started/install)
* **Android Studio:** [Scarica qui](https://developer.android.com/studio) (necessario per l'emulatore e l'SDK Android).
* **Visual Studio Code (Consigliato):** [Scarica qui](https://code.visualstudio.com/) come editor di testo principale.
* **Git:** Per clonare il progetto.
* **Xcode (Solo per macOS):** Necessario per compilare ed eseguire la versione iOS.

---

## Configurazione Iniziale

1.  **Clona la repository:**
    ```bash
    git clone https://github.com/nicogarbin/VEnv.git
    cd VEnv
    ```

2.  **Configurazione Visual Studio Code:**
    * Apri VS Code e vai nella sezione **Extensions** (Ctrl+Shift+X).
    * Cerca e installa l'estensione ufficiale **"Flutter"** (che installerà automaticamente anche Dart).
    * Apri la cartella del progetto `VEnv` in VS Code.

3.  **Installa le dipendenze di Flutter:**
    Esegui il comando dalla cartella principale del progetto:
    ```bash
    flutter pub get
    ```

4.  **Verifica lo stato del sistema:**
    Controlla che non manchino componenti fondamentali:
    ```bash
    flutter doctor
    ```
    *Nota: Se vedi errori relativi alle licenze Android, risolvile con: `flutter doctor --android-licenses`.*

---

## Avvio su Emulatore (Android Studio)

### Per Android (Windows/macOS/Linux)
1.  Apri **Android Studio**.
2.  Vai su **Device Manager** (icona del cellulare nella barra laterale destra o nel menu *Tools*).
3.  Seleziona un dispositivo virtuale e clicca sul tasto **Play** per avviarlo.
4.  Una volta avviato l'emulatore, torna nel terminale del progetto e digita:
    ```bash
    flutter run
    ```

### Per iOS (Solo macOS)
1.  Apri il simulatore iOS tramite terminale:
    ```bash
    open -a Simulator
    ```
2.  Una volta avviato, esegui l'app:
    ```bash
    flutter run
    ```
    
---

## Installazione su Dispositivo Fisico (Android)

Puoi installare VEnv direttamente sul tuo smartphone Android senza usare l'emulatore.

### Opzione A: Creazione del file APK (Manuale)
1.  Genera il pacchetto di installazione:
    ```bash
    flutter build apk --release
    ```
2.  Troverai il file APK in questo percorso:
    `build/app/outputs/flutter-apk/app-release.apk`
3.  Invia questo file al tuo telefono (tramite cavo, email o cloud) e aprilo per installarlo (accetta l'installazione da "Origini sconosciute" se richiesto).

### Opzione B: Installazione via USB (Debug Mode)
1.  Collega il telefono al PC con un cavo USB.
2.  Attiva le **Opzioni Sviluppatore** sul telefono e abilita il **Debug USB**.
3.  Verifica che il PC veda il telefono con il comando:
    ```bash
    flutter devices
    ```
4.  Lancia l'installazione diretta:
    ```bash
    flutter run --release
    ```
