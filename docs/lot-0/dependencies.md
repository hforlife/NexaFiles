# Audit des dépendances — état au 1 octobre 2026

Les versions sont celles vues dans les registres le jour de l'audit. Elles devront être figées par lockfile après mise à niveau du SDK et vérifiées par SBOM avant publication.

| Domaine | Candidat | Version auditée | Activité / natif | Licence | Décision provisoire |
|---|---|---:|---|---|---|
| SAF | API Android `ContentResolver`, `DocumentsContract`, `DocumentFile` | AndroidX 1.0.1 | API officielle, Kotlin | Apache-2.0 | **Retenir** derrière `StorageRepository`; contrôle maximal et surface réduite |
| SAF | `saf` | 2.1.2 | actif; plugin Kotlin | licence à revérifier dans l'artefact | challenger intéressant, non adopté sans test/device et audit source |
| PDF | `pdfrx` | 2.6.5 | très actif; PDFium natif | MIT; PDFium BSD-3-Clause + avis tiers | **Candidat préféré**: recherche texte, mots/texte, mot de passe, viewer riche |
| PDF | `pdfx` | 2.11.0 | actif; Android `PdfRenderer` | MIT | challenger; API plus simple, recherche texte absente sur Android natif |
| EPUB | `flutter_epub_viewer` | 2.0.0 | actif; Epub.js + InAppWebView | BSD-3-Clause; dépendances à auditer | **Candidat préféré**: CFI, recherche, thèmes, sélection; coût WebView |
| EPUB | `epub_view` | 3.3.0 | reprise récente après longue pause; Dart/HTML | MIT | prototype B; pagination/progression moins robuste au reflow |
| EPUB | `epubx` | transitif | Dart pur | MIT | parseur, pas moteur de lecture complet |
| ZIP/CBZ | `archive` | 4.2.0 actuel; spike épinglé 3.6.1 pour Dart 3.2 | actif; Dart, I/O orienté fichiers en 4.x | MIT | **Retenir après upgrade**; revalider le vrai lazy decode et la mémoire |
| RAR/CBR | `junrar` | branche active, jalons RAR5 récents | Java pur | Apache-2.0 | **Challenger préféré**, validation RAR4/RAR5/solid obligatoire |
| RAR/CBR | UnRAR officiel | version à figer | C++/JNI | freeware avec restriction anti-reconstruction | écarter par défaut; risque licence/maintenance JNI |
| 7Z/CB7 | Apache Commons Compress | release courante à figer | Java; XZ Java | Apache-2.0 | **Candidat préféré**; seekable channel, solides séquentiels/cache temporaire |
| 7Z/RAR | 7-Zip-JBinding Android | moteur 16.02 ancien | JNI, ABI multiples | LGPL-2.1+ et composants/restriction UnRAR | écarté V1 sauf échec mesuré des solutions Java |
| DB | `drift` + SQLite | à figer au Lot 1 | actif, natif SQLite | MIT / domaine public SQLite | recommandé pour bibliothèque/historique, hors spike lecteur |
| cache | `path_provider` + index Drift, LRU maison | à figer | officiel Flutter | BSD-3-Clause/MIT | recommandé; quotas et nettoyage atomique applicatifs |
| MIME | `mime` + `FormatDetector` interne | à figer | Dart | BSD-3-Clause | MIME comme signal, jamais comme preuve unique |
| miniatures | Android `ContentResolver.loadThumbnail` | API 29+ | natif officiel | SDK Android | retenir avec fallback rendu page/image |

Sources primaires: [SAF Android](https://developer.android.com/training/data-storage/shared/documents-files), [pdfrx](https://pub.dev/packages/pdfrx), [pdfx](https://pub.dev/packages/pdfx), [flutter_epub_viewer](https://pub.dev/packages/flutter_epub_viewer), [epub_view](https://pub.dev/packages/epub_view), [archive](https://pub.dev/packages/archive), [Commons Compress](https://commons.apache.org/proper/commons-compress/), [limites 7z](https://commons.apache.org/proper/commons-compress/limitations.html), [PDFium LICENSE](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE), [7-Zip-JBinding](https://github.com/borisbrodski/sevenzipjbinding), [junrar](https://github.com/junrar/junrar).

## Compatibilité commerciale

MIT, BSD-3-Clause et Apache-2.0 permettent une application commerciale avec conservation des notices. LGPL autorise en principe le lien dynamique mais impose des obligations de remplacement/relink et de fourniture des sources de la bibliothèque modifiée; une revue juridique reste nécessaire. Le code UnRAR interdit son usage pour reconstruire l'algorithme RAR: l'extraction commerciale n'est pas interdite, mais cette licence non standard accroît le risque. Aucun moteur ne sera intégré sans génération d'un inventaire des licences transitives.
