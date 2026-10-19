# Architecture proposée pour la V1

Une architecture par fonctionnalité, avec quatre couches légères, évite une Clean Architecture cérémonielle:

```text
lib/features/{storage,readers,archives,library,history,preferences,monetization}/
  presentation/   widgets + état UI
  application/    cas d'usage et orchestration
  domain/         contrats et modèles sans Flutter
  infrastructure/ adapters SAF/PDFium/WebView/ZIP/Java
lib/core/{cache,formats,errors,telemetry}/
```

- `StorageRepository`: arbres accordés, navigation, métadonnées, mutations transactionnelles; renvoie des `ContentSource`.
- `ContentSource`: lecture séquentielle; capability `SeekableContentSource` distincte.
- `FormatDetector`: score signatures → structure interne → MIME → extension; ZIP inspecté pour `mimetype` EPUB ou majorité d'images.
- `ReaderRegistry`: choisit un `ReaderAdapter` selon détection/capabilities. `ReaderSession` possède ressources, progression et `dispose`.
- `ArchiveRegistry`: ZIP Dart, RAR Java, 7z Java; expose les capacités (random/sequential/solid).
- `ArchiveSafetyPolicy`: limites avant et pendant chaque extraction.
- `ComicPageSource`: contrat commun; backends directory/zip/rar/7z, cache/préchargement invisibles au lecteur.
- `LibraryRepository`: catalogue Drift; jamais propriétaire du fichier utilisateur.
- `ReadingProgressRepository`: PDF page+offset, EPUB CFI, comics index+identité entrée.
- `CacheManager`: cache privé, quotas, réservations d'espace, journal/cleanup et LRU.

Les appels natifs lourds tournent hors UI. Le registre dépend d'interfaces, mais aucune classe/interface supplémentaire sans second backend ou frontière de test réelle.
