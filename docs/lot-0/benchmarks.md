# Benchmarks Lot 0

## Protocole reproductible

Appareil de référence à définir (au minimum Android 10 bas de gamme, Android 13 milieu de gamme, Android 16 récent), release/profile build, mode avion, batterie >50 %, température stabilisée. Corpus versionné par SHA-256: PDF texte 1k pages, PDF image ≥500 Mio, EPUB petit/gros, CBZ 20/200/500+, RAR4/RAR5 solide/non solide, 7z solide/non solide. Dix exécutions cold + dix warm.

Mesures: `coldOpenTime`, `firstPageTime`, p50/p95 `pageLoadTime`, `peakMemory` via `adb shell dumpsys meminfo`, `cacheUsage`, `indexingTime`, `extractionTime`, CPU et disque temporaire. Vider uniquement le cache du spike entre cold runs; conserver logs JSON bruts avec modèle/appareil/API/build/corpus.

## Résultats

| Moteur | Corpus | cold open | première page | page p95 | pic RAM | cache/disque | Statut |
|---|---|---:|---:|---:|---:|---:|---|
| Tous | — | — | — | — | — | — | **NON MESURÉ**: SDK Flutter local crash; aucun appareil/corpus |

Le crash reproductible survient avec Flutter 3.16.9 / Dart 3.2.6 sur macOS x64 dans `cpuinfo_macos.cc:42`, code 134, pour `flutter pub get` et `flutter test`. En revanche `android/gradlew assembleDebug` réussit en 2 min 33 s et produit un APK; cela valide la compilation Kotlin/packaging, pas le comportement ni les performances.
