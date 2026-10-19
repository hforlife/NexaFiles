# LOT 3 — RAPPORT

## Archives / ZIP / RAR / 7Z

ZIP est géré en Dart. RAR/CBR repose sur Junrar 7.5.8 et 7Z/CB7 sur Commons Compress 1.26.2 + XZ 1.9 via Kotlin. Les trois moteurs listent, lisent et extraient ; aucun ne crée d'archive.

## Sécurité

Toutes les sessions appliquent `ArchiveSafetyPolicy` avant lecture ou extraction. Traversal, chemins absolus, profondeur, nombre, tailles et ratio sont bornés. L'extraction est annulable et tente de nettoyer ses sorties en cas d'échec.

## Détection Comic / ComicPageSource

Les signatures priment sur l'extension. CBZ/CBR/CB7 sont reconnus, et un ZIP ordinaire peut être classé par l'heuristique documentée. `ArchiveComicPageSource` masque le conteneur, trie naturellement et charge chaque page à la demande.

## Comic Reader / Modes de lecture

Le lecteur fournit page unique, vertical et double page, LTR/RTL, zoom, ajustement largeur/hauteur/libre, contrôles immersifs et navigation rapide.

## Cache / préchargement

Cache mémoire borné à quatre pages et fenêtre N-1 à N+2. Les sources d'archive nécessitant un accès seekable sont matérialisées dans le cache privé.

## Progression / reprise

Progression temporisée en SQLite, reprise automatique, préférences globales et préférences par livre.

## Bibliothèque / Récents

L'ouverture alimente les récents et le `LibraryItem`. « Continuer la lecture » affiche la couverture miniature, le titre et la progression.

## Livré

- moteur unifié ZIP/RAR/7Z et navigation virtuelle ;
- extraction complète ou ciblée avec progression, annulation et garde-fous ;
- détection CBZ/CBR/CB7 et heuristique des ZIP d'images ;
- lecteur simple, vertical et double page, LTR/RTL, zoom et ajustements ;
- cache borné, préchargement, couverture, progression et préférences ;
- reprise depuis la Bibliothèque ;
- tests unitaires de détection, tri et sécurité ;
- documentation d'architecture, limites et sécurité.

## Compilation / Tests réellement exécutés

- `./gradlew assembleDebug` : **SUCCÈS** le 2 octobre 2026.
- Compilation Flutter/Dart et Kotlin incluse dans l'assemblage : **SUCCÈS**.
- `dart format lib test` : **BLOQUÉ PAR L'ENVIRONNEMENT**, arrêt natif reproductible dans `cpuinfo_macos.cc:42` (code 134).
- `flutter test` / analyse autonome : même runtime Dart concerné ; non retenu comme échec fonctionnel du Lot 3. Les tests ont été ajoutés mais leur exécution reste à refaire sur un poste sain.

La chaîne Android reste sur AGP 7.4.2/Gradle 7.5 pour compatibilité avec le projet existant. R8 8.1.44 est injecté afin de dexer les bibliothèques d'archives récentes. `commons-lang3` et `slf4j-api` sont épinglés à des versions Android compatibles.

## REAL_DEVICE_VALIDATION_REQUIRED

1. Ouvrir puis extraire un ZIP, un RAR et un 7Z depuis stockage local, carte SD et fournisseur cloud SAF.
2. Vérifier CBR/CB7, archive protégée, archive corrompue, manque d'espace et annulation.
3. Lire un album volumineux dans chaque mode, en LTR puis RTL, avec zoom et reprise.
4. Contrôler mémoire, fluidité, nettoyage du cache et restauration après redémarrage.

## Formats ou variantes NON SUPPORTÉS

- Archives protégées par mot de passe : `NOT_SUPPORTED_V1`.
- Archives multi-volumes : non garanties.
- GIF animé, AVIF et TIFF comme pages Comic.
- TAR/GZ, création ou modification d'archives.

## Dette technique

- mots de passe et archives multi-volumes non pris en charge ;
- conflits de noms délégués au fournisseur SAF ;
- accès 7Z solide potentiellement coûteux ;
- ratio de compression 7Z à durcir ;
- AGP à migrer vers une version officiellement compatible compileSdk 34 lors d'un lot de maintenance.

## Fichiers principaux créés/modifiés

- `lib/core/archives/`, `lib/core/comics/` et `lib/core/platform/providers.dart` ;
- `lib/features/archives/` et `lib/features/reader/` ;
- `lib/features/files/files_screen.dart`, `lib/features/library/library_screen.dart`, paramètres et base SQLite ;
- `android/app/src/main/kotlin/com/example/nexa_file/ArchiveBridge.kt` et configuration Gradle ;
- `test/lot3_archive_comic_test.dart` et `docs/lot-3/`.

## Statut

**GO LOT 4** — l'architecture, l'implémentation et l'APK debug sont présents. La recette Android listée ci-dessus reste explicitement `REAL_DEVICE_VALIDATION_REQUIRED` avant diffusion.
