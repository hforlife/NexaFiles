# Rapport final — Lot 0

## 1. Résumé exécutif

Le travail produit un socle de spike SAF/CBZ/détection/sécurité et un audit actuel, mais **le Lot 0 n'est pas clos**: la chaîne Flutter locale plante, aucun appareil ni corpus n'est disponible, donc PDF, EPUB, RAR, 7Z, persistance SAF et performances ne sont pas validés expérimentalement. Décision: **NO-GO pour figer les dépendances ou commencer le Lot 1; GO conditionnel pour poursuivre le Lot 0 après remise à niveau de l'environnement**.

## 2. Environnement de test

macOS x64; Flutter 3.16.9, Dart 3.2.6, Java 17.0.12. Aucun `adb` utilisable/appareil listé, ni `7z`/`unrar`; `bsdtar` présent. `flutter --version`, `flutter pub get` et `flutter test` terminent code 134 dans `cpuinfo_macos.cc:42`. L'assemblage direct `./gradlew assembleDebug` réussit toutefois en 2 min 33 s (APK 145,7 Mo), ce qui valide le pont Kotlin au niveau compilation. Projet sans dépôt Git détecté.

## 3. Packages étudiés

Voir [dependencies.md](dependencies.md). Les décisions restent provisoires tant que les deux meilleurs candidats de chaque domaine critique ne sont pas benchmarkés.

## 4. Storage / SAF

Solution: API Android native derrière `StorageRepository`, URI opaques et grants persistants. Prototype compilé: picker, grants, liste, métadonnées, lecture et mutations simples. Limites: copie/déplacement fallback par flux; providers variables; test appareil/restart manquant. Statut **VALIDÉ AVEC LIMITATIONS (conception/compilation), NON VALIDÉ (runtime)**.

## 5. PDF

`pdfrx` préféré à `pdfx` pour texte/recherche et PDFium, sous réserve du benchmark. Tous les scénarios runtime sont **NON VALIDÉS**. Voir [pdf.md](pdf.md).

## 6. EPUB

Epub.js via `flutter_epub_viewer` préféré à `epub_view` pour CFI et reflow; sécurité WebView obligatoire. **NON VALIDÉ**. Voir [epub.md](epub.md).

## 7. ZIP / CBZ

Prototype Dart présent: index, filtre images, tri naturel, page demandée, LRU/préchargement. Tests écrits; exécution et mémoire **NON VALIDÉES** à cause du SDK.

## 8. RAR / CBR

`junrar` est le premier candidat (Apache-2.0); archives solides nécessiteront cache séquentiel. **NON VALIDÉ**.

## 9. 7Z / CB7

Apache Commons Compress est le premier candidat; canal seekable/copie SAF et cache des solides. **NON VALIDÉ**.

## 10. Sécurité

Politique implémentée pour traversal, limites/ratios/profondeur/espace. Extraction transactionnelle et contrôle d'octets réels spécifiés. Tests fuzz/corpus **NON VALIDÉS**.

## 11. Benchmarks

Aucune performance observée. Protocole et tableau honnête dans [benchmarks.md](benchmarks.md).

## 12. Licences

Préférence MIT/BSD/Apache. PDFium exige notices. LGPL/UnRAR nécessitent validation juridique et sont évités par défaut. Ne pas créer de RAR. Générer SBOM/notices avant release.

## 13. Architecture recommandée

Architecture feature-first à couches `presentation/application/domain/infrastructure`, registries de lecteurs/archives, sources à capabilities et cache privé borné. Voir [architecture-proposal.md](architecture-proposal.md).

## 14. Décision concernant Rust

**NON.** Aucun besoin mesuré ne le justifie; Kotlin/Java couvre SAF, RAR et 7z, Dart couvre orchestration/ZIP. Réouvrir seulement après benchmark démontrant un goulot précis.

## 15. Dépendances proposées pour la V1

Provisoires: API SAF native + DocumentFile, `pdfrx`, `flutter_epub_viewer`, `archive` 4.x, `junrar`, Apache Commons Compress/XZ, Drift/SQLite, `path_provider`, `mime`. Ne pas les figer avant les matrices runtime.

## 16. Risques encore ouverts

Compatibilité Flutter récente/minSdk/ABI, providers SAF cloud, coût copie URI, PDF protégés/malformés, CSP WebView et EPUB complexes, RAR5/solides, codecs 7z rares, pics RAM, quotas disque et licences transitives.

## 17. GO / NO-GO du projet

- **VALIDÉES**: principes URI ≠ path; interfaces `ContentSource`/`ComicPageSource`; signatures PDF/ZIP/RAR/7z; tri naturel et politique de sécurité au niveau code/revue.
- **VALIDÉES AVEC LIMITATIONS**: architecture SAF et CBZ; candidats/licences sur documentation, sans runtime.
- **NON VALIDÉES**: grants après redémarrage, opérations SAF multi-provider, moteurs PDF/EPUB, CBR/CB7, archives corrompues réelles, RAM/fluidité/temps, appareil Android.

Conclusion: la faisabilité globale est forte, mais **NO-GO Lot 1** tant que le SDK n'est pas remplacé et la campagne instrumentée exécutée. Aucun développement de l'application finale n'a commencé.
