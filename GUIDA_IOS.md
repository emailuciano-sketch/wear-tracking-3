# Guida Completa alla Compilazione e Installazione su iOS (`Wear-Tracking 3`)

Il progetto Flutter `wear_tracking_flutter` è ora **completamente configurato per iOS**:
- **Nome App:** `Wear-Tracking 3`
- **Bundle Identifier iOS:** `com.wear.tracking.v3`
- **Versione minima iOS:** `iOS 15.0`
- **Server Traccar predefinito:** `https://pedinatore.com` (HTTPS + WSS, conforme ad App Transport Security di Apple senza eccezioni insicure)
- **Google Maps SDK for iOS:** configurato in `ios/Runner/AppDelegate.swift` e `ios/Runner/Info.plist` (`GMSApiKey`)
- **CocoaPods:** configurato in `ios/Podfile`
- **Icone iOS (`AppIcon.appiconset`):** tutte le 15 risoluzioni generate (incluso `1024x1024` RGB a 24 bit senza trasparenza/canale alpha, richiesto da App Store Connect)

---

## 1. Abilitare la chiave Google Maps per iOS (su Google Cloud Console)
1. Apri la [Google Cloud Console](https://console.cloud.google.com/apis/library).
2. Seleziona il progetto legato alla tua chiave API (`AIzaSyBf-GnDwUSfsE_qTGkb1wVZK6JxYgm-dMs`).
3. Vai in **APIs & Services → Library**, cerca **Maps SDK for iOS** e clicca **Enable (Abilita)**.
4. Vai in **APIs & Services → Credentials**:
   - Se la chiave attuale è limitata solo alle app Android, crea una seconda chiave per iOS (limitata a **iOS apps** con Bundle ID `com.wear.tracking.v3`) e incollala nel campo `GMSApiKey` dentro `ios/Runner/Info.plist` (e in `ios/Runner/AppDelegate.swift`).
   - Se la chiave attuale non ha restrizioni di piattaforma, funzionerà immediatamente non appena abiliti **Maps SDK for iOS**.

---

## 2. Come compilare e installare su iPhone

Poiché Apple richiede **macOS + Xcode** per firmare e generare il pacchetto iOS, puoi scegliere una delle due modalità seguenti:

### Modalità A — Compilazione su un Mac (con Xcode)
1. Copia la cartella `wear_tracking_flutter` sul Mac.
2. Apri il Terminale sul Mac dentro la cartella `wear_tracking_flutter` ed esegui:
   ```bash
   flutter pub get
   cd ios && pod install && cd ..
   ```
3. Apri `ios/Runner.xcworkspace` in **Xcode**:
   - Clicca su **Runner** (a sinistra) → scheda **Signing & Capabilities**.
   - Spunta **Automatically manage signing**.
   - Seleziona il tuo **Team** (puoi accedere in *Xcode → Settings → Accounts* anche con un normale Apple ID gratuito per testare sul tuo iPhone via cavo USB, oppure con un account Apple Developer da 99$/anno per TestFlight e App Store).
   - Verifica che **Bundle Identifier** sia `com.wear.tracking.v3`.
4. Collega l'iPhone via USB (sull'iPhone attiva *Impostazioni → Privacy e sicurezza → Modalità sviluppatore*), seleziona l'iPhone in Xcode e premi **Run (▶)** oppure da terminale:
   ```bash
   flutter run --release
   ```
5. Per generare il file `.ipa` da distribuire:
   ```bash
   flutter build ipa --release
   ```

---

### Modalità B — Compilazione in Cloud da Windows (senza Mac)
Nel progetto sono già pronti sia il file **`codemagic.yaml`** (per [Codemagic.io](https://codemagic.io)) sia **`.github/workflows/ios-build.yml`** (per GitHub Actions con runner `macos-latest`):

1. Carica la cartella `wear_tracking_flutter` su un repository privato **GitHub**.
2. **Con GitHub Actions (gratuito):**
   - Appena fai push su GitHub (o premi *Run workflow* nella scheda **Actions** → *Build iOS App*), GitHub avvia una macchina virtuale macOS, installa Flutter e CocoaPods, verifica il codice e produce il pacchetto `Wear-Tracking-3-iOS` scaricabile dalla sezione **Artifacts**.
3. **Con Codemagic + TestFlight (consigliato per installare direttamente su iPhone senza Mac):**
   - Accedi a [Codemagic.io](https://codemagic.io) con il tuo account GitHub e seleziona il repository.
   - Nella sezione **Code signing** di Codemagic collega il tuo account **Apple Developer Program** (genera automaticamente certificato di distribuzione e Provisioning Profile per `com.wear.tracking.v3`).
   - Avvia la build: Codemagic compila l'`.ipa` firmata su un Mac M2 e la invia direttamente all'app **TestFlight** sul tuo iPhone.
