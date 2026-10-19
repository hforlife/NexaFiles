# LOT 1 — RAPPORT

## Architecture

Socle feature-first `app/core/features/shared`, Riverpod sobre, router central et Material 3. Les prototypes Lot 0 restent séparés.

## Fonctionnalités réalisées

Navigation Fichiers/Bibliothèque/Récents/Outils, Paramètres, thèmes système/clair/sombre persistants, langue FR/EN persistante, états vides/chargement/erreur, ajout de racine SAF, services formats/readers/archives/comics/cache et erreurs utilisateur.

## Base de données

Drift/SQLite initialisé au bootstrap avec schéma version 1: bibliothèque, progression JSON, signets, récents et racines. Modèle `LibraryItem` et locators PDF/Comic/EPUB présents.

## Android/SAF

Pont Kotlin de production compilé. Picker, grants, liste, métadonnées, lecture et mutations de fichiers exposés sans path classique. Dossiers récursifs non implémentés.

## Readers

Registry/adapter/session prêts; routes réservées; aucun faux lecteur complet.

## Archives

Registry, entries et politique de sécurité. CBZ/dossier implémentés; RAR/7Z reportés.

## UI

Material 3 clair/sombre, navigation tactile, écrans structurés sans fausses données, actions futures explicitement désactivées. L'i18n est centralisée dans `AppStrings` pour le socle; les messages d'erreur techniques restants devront rejoindre les ressources localisées.

## Tests réellement exécutés

- `./gradlew assembleDebug`: réussi (application complète).
- assemblage ciblé `lib/core/compile_check.dart`: réussi et couvre les modules core hors graphe UI.
- tests unitaires écrits: tri naturel, détection, structure ZIP comic, sécurité et locator.
- `flutter test`: non exécutable dans cet environnement à cause du crash Dart/macOS déjà documenté.

## Limitations environnement

Flutter 3.16.9/Dart 3.2.6 et Android Gradle Plugin 7.3 sont anciens. Compilation avec SDK 34 réussie mais produit un avertissement AGP. La mise à niveau de la chaîne doit précéder la publication.

## REAL_DEVICE_VALIDATION_REQUIRED

SAF complet et redémarrage, SQLite sur cycle de vie Android, thèmes/ergonomie, gros CBZ, cache/disque, PDF/EPUB/CBR/CB7, RAM et performances.

## Dette technique

Navigation détaillée des sous-dossiers, copie récursive, collisions/cancel, repositories bibliothèque/progression, cache LRU sur disque, génération i18n ARB et migrations futures. Les versions de dépendances sont temporairement compatibles avec l'ancien SDK.

## Décisions importantes

Rust absent; URI opaques; conteneur/contenu séparés; progression JSON; tables différées tant qu'inutilisées; actions futures désactivées plutôt que boutons morts.

## Statut

**GO LOT 2**, sous réserve de conserver les validations appareil explicites. Ne pas commencer le Lot 2 sans accord.
