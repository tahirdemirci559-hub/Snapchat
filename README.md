# ⚡️ Pling – Snaps, Chats & Stories für Familie und Freunde

Pling ist eine iPhone-App in **SwiftUI**, die so funktioniert wie Snapchat: Fotos aufnehmen,
bemalen und beschriften, als Snap verschicken (verschwindet nach dem Ansehen), chatten,
Gruppen erstellen und Stories posten, die nach 24 Stunden weg sind.

> **Warum „Pling“ und nicht „Snapchat“?** „Snapchat“ ist eine eingetragene Marke von Snap Inc.
> Deshalb hat die App einen eigenen Namen, eigene Farben (lila/pink statt gelb) und ein
> eigenes Logo. Die Bedienung ist aber ganz ähnlich.

## Funktionen

| Bereich | Was geht |
|---|---|
| 📷 **Kamera** | Live-Kamera, Vorder-/Rückkamera (Doppeltippen), Blitz, Foto aus der Galerie, 🙂-Test-Snap (für den Simulator) |
| 🎨 **Snap-Editor** | Text-Balken (verschiebbar), Zeichnen in 8 Farben mit Rückgängig, 7 Filter, Timer (3 / 5 / 10 s / ∞), in Fotos speichern |
| 🚀 **Senden an …** | Mehrere Freunde, Gruppen und „Meine Story“ auf einmal |
| 💬 **Chats** | 1:1- und Gruppenchats, Status wie *Neuer Snap / Gesendet / Geöffnet*, 🔥 Flammen-Serie, Suche, Nachrichten kopieren/löschen |
| 👻 **Snaps** | Vollbild mit Countdown – danach wird das Bild gelöscht |
| 📖 **Stories** | Kreise + Kacheln zum Durchscrollen, Fortschrittsbalken, Tippen = weiter/zurück, nach unten wischen = schließen, auf Stories antworten, eigene Aufrufe sehen |
| 👥 **Freunde** | Per Benutzername hinzufügen, Profil teilen, entfernen (wischen) |
| 🙂 **Profil** | Name, Emoji-Avatar und Farbe ändern |

Bedienung wie bei Snapchat: **Links Chats ← Mitte Kamera → rechts Stories.** Man kann wischen
oder unten auf die Symbole tippen.

## Starten (Demo-Modus)

Du brauchst einen **Mac mit Xcode 16 oder neuer**. Die App läuft ab **iOS 17**.

1. Repository herunterladen und `Pling.xcodeproj` öffnen.
2. Links das Projekt **Pling** → Target **Pling** → **Signing & Capabilities** → bei *Team* deine Apple-ID wählen.
   Falls nötig, den *Bundle Identifier* ändern (z. B. `de.deinname.pling`).
3. Oben ein iPhone oder einen Simulator wählen und ▶︎ drücken.

Ohne weitere Einrichtung startet Pling im **Demo-Modus**: Alles bleibt auf dem Gerät, und
**Mama, Papa, Lena** sind Test-Freunde, die auf Nachrichten antworten und Snaps „öffnen“.
**Opa** kannst du selbst über den Benutzernamen `opa` hinzufügen.

> Im Simulator gibt es keine Kamera. Tippe dort auf 🙂 oder wähle ein Foto aus der Galerie.

## Online-Modus: Mit Familie und Freunden schreiben

Damit ihr euch über verschiedene iPhones schreiben könnt, braucht die App einen Server.
Dafür nutzt Pling **Firebase** (von Google, für kleine Gruppen kostenlos). Einmalig einrichten:

1. **Firebase-Projekt anlegen:** <https://console.firebase.google.com> → *Projekt hinzufügen*.
2. **iOS-App registrieren:** im Projekt auf das iOS-Symbol → *Bundle-ID* genau wie in Xcode eintragen →
   **`GoogleService-Info.plist` herunterladen** und in Xcode in den Ordner `Pling` ziehen
   (Haken bei *Copy items if needed* und beim Target *Pling*).
3. **Anmeldung aktivieren:** *Authentication* → *Sign-in method* → **Anonym** einschalten.
4. **Datenbank anlegen:** *Firestore Database* → *Datenbank erstellen* (Standort z. B. `europe-west3`, Frankfurt) →
   unter **Regeln** den Inhalt von [`firestore.rules`](firestore.rules) einfügen → *Veröffentlichen*.
5. **Firebase-Paket in Xcode einbinden:** *File → Add Package Dependencies…* → URL
   `https://github.com/firebase/firebase-ios-sdk` → Produkte **FirebaseAuth** und **FirebaseFirestore**
   zum Target *Pling* hinzufügen.
6. App neu starten. Im Profil steht jetzt **Modus: Online (Firebase)**.

Den Rest erledigt die App selbst: Ist das Firebase-Paket eingebunden und die `GoogleService-Info.plist`
vorhanden, nutzt sie Firebase, sonst den Demo-Modus (`AppStore.makeDefault()`).

**Auf die iPhones der Familie bringen:** Jedes Gerät per Kabel an den Mac anschließen und in Xcode
ausführen. Mit einer kostenlosen Apple-ID läuft die App 7 Tage, dann einfach neu installieren. Mit dem
Apple Developer Program (99 €/Jahr) geht das bequemer über **TestFlight** und ohne Ablaufdatum.

Danach in der App: Jede Person legt einen Benutzernamen an, teilt ihn (Profil → *Profil teilen*), und
die anderen fügen sie über ➕ hinzu.

### Gut zu wissen

- Das Konto hängt am Gerät (anonyme Anmeldung). Wer die App löscht oder sich abmeldet, braucht ein neues Konto.
- Snaps werden nach dem Ansehen auf dem Server gelöscht. Screenshots kann man trotzdem machen,
  also nichts schicken, was nicht gesehen werden soll.
- Bilder werden verkleinert (max. 1280 px) und direkt in Firestore gespeichert. Das reicht für
  Familie und Freunde und braucht kein extra Firebase Storage.

## Projektaufbau

```
Pling/
├── App/PlingApp.swift            App-Start, Lade- und Startbildschirm
├── Models/Models.swift           Benutzer, Nachricht, Chat, Story (+ Flammen-Serie)
├── Services/
│   ├── ChatBackend.swift         Schnittstelle zum Server
│   ├── LocalBackend.swift        Demo-Modus mit Test-Freunden
│   ├── FirebaseBackend.swift     Online-Modus (nur wenn Firebase eingebunden)
│   └── ImageTools.swift          Filter, Komprimierung, Bild-Cache
├── Store/AppStore.swift          Zentraler App-Zustand
└── Views/
    ├── MainView.swift            Wischen zwischen Chats / Kamera / Stories
    ├── OnboardingView.swift      Registrierung
    ├── Camera/                   Kamera, Snap-Editor, „Senden an …“
    ├── Chat/                     Chat-Liste, Chat, Snap-Anzeige, neuer Chat
    ├── Stories/                  Stories-Seite und Story-Anzeige
    ├── Profile/                  Profil und Freunde
    └── Components/Theme.swift    Farben, Avatar, Hinweise
```

Der Ordner `Pling` ist in Xcode ein *synchronisierter Ordner*: Neue `.swift`-Dateien, die du dort
anlegst, gehören automatisch zur App.

## Ideen für später

- Login mit „Mit Apple anmelden“, damit das Konto auf neue Geräte mitkommt
- Push-Mitteilungen bei neuen Snaps (Firebase Cloud Messaging)
- Videos-Snaps, Sprachnachrichten, Sticker
- Karte mit Freunden (Standort freiwillig teilen)
