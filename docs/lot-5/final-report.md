# LOT 5 — RAPPORT

## LibraryRepository

`LibraryRepository`, `ReadingProgressRepository`, `BookmarkRepository` et `CollectionRepository` encapsulent les opérations métier et la base.

## Scanner / Indexation

Racines SAF configurables, parcours séquentiel annulable, formats ciblés, métadonnées EPUB, erreurs isolées et actualisation manuelle. Aucun scan lourd au démarrage.

## Déduplication

URI source unique et upsert SQLite. L'incrément compare URI, taille et `modifiedAt`. Les fichiers disparus sont marqués indisponibles.

## Bibliothèque

Grille responsive, couvertures/placeholder, progression, Continuer la lecture, Récemment ajoutés, fiche détaillée et reprise via les lecteurs existants.

## Recherche / filtres / tris

Recherche titre/fichier/auteur ; catégories EPUB/Comic/PDF/Documents ; filtres en cours/terminés/non lus/favoris ; cinq tris.

## Continuer la lecture

Éléments accessibles avec progression supérieure à zéro et inférieure à 95 %, triables par dernière lecture.

## Collections

CRUD et relation plusieurs-à-plusieurs. La suppression ne touche jamais aux fichiers.

## Favoris / Statut lecture

Favoris persistants. Statuts dérivés avec seuil de fin 95 %, surcharge manuelle possible.

## Signets

Liste depuis la fiche ; un toucher place la progression sur le locator puis ouvre le lecteur.

## Couvertures

Réutilisation de `CacheManager/covers`, chargement avec résolution bornée et placeholders cohérents EPUB/PDF/Comic/Document.

## Base / migrations

Schéma v4 additif : métadonnées et état sur `library_items`, `library_scan_roots`, `collections`, `collection_items`. Chemin de migration conservé depuis v1.

## Compilation

`./gradlew assembleDebug` : **SUCCÈS** le 2 octobre 2026. APK debug généré.

## Tests réellement exécutés

Tests légers ajoutés pour fallback titre, statut, seuil, formats indexables et identité URI. Leur exécution autonome reste bloquée par `cpuinfo_macos.cc:42`; les sources de production compilent via Gradle.

## REAL_DEVICE_VALIDATION_REQUIRED

Scan de centaines/milliers de fichiers, SD/USB/cloud, interruption, retrait permission, couvertures lourdes, scrolling, performances SQLite, mémoire, reprise et migration d'une installation existante.

## Dette technique

Pagination SQL pour des bibliothèques très volumineuses, journal détaillé des erreurs, métadonnées PDF enrichies et écran dédié au contenu d'une collection.

## Statut

**GO LOT 6**
