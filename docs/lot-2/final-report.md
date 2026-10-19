# LOT 2 — RAPPORT

## Gestionnaire de fichiers

Module utilisable implémenté: racines SAF persistées, état inaccessible, favoris, navigation, listing réel et opérations de gestion.

## Navigation

Pile URI multi-niveaux, breadcrumb horizontal, retour prioritaire à la fermeture de sélection puis au dossier parent, pull-to-refresh.

## SAF

Le pont Kotlin couvre lecture, métadonnées, création, renommage, suppression, copie, déplacement, partage et ouverture externe. Aucune conversion en path.

## Opérations

Création et validation de nom, renommage avec contrôle de conflit, suppression simple/multiple avec confirmation et bilan partiel, copie/déplacement avec dialogue de destination, progression et annulation coopérative.

## Copie/déplacement

Copie récursive de dossiers en Dart; déplacement = copie réussie puis suppression. Les sources sont préservées en cas d'échec avant achèvement.

## Conflits

Remplacer, conserver les deux, ignorer, annuler. Les suffixes `(n)` préservent l'extension.

## Sélection multiple

Appui long, ajout/retrait, tout sélectionner, annuler, barre Copier/Déplacer/Partager/Supprimer et retour Android prioritaire.

## Recherche/tri

Recherche locale insensible à la casse. Tri nom naturel/date/taille/type, ascendant/descendant et dossiers groupés. Modes liste/grille persistés.

## Partage/Ouvrir avec

Sharesheet Android simple/multiple et `ACTION_VIEW` via URI SAF avec grants temporaires. Aucun path artificiel.

## Récents

Une ouverture enregistre/met à jour `library_items` et `recent_items`. L'onglet affiche les données réelles et traite les fichiers disparus.

## UI/UX

AppBar contextuelle, menus/dialogs/bottom sheets, états première utilisation/dossier vide/recherche vide/erreur, informations fichier et racines favorites.

## Tests réellement exécutés

Tests écrits pour validation de noms, conflits, tri naturel/groupement, détection, sécurité et locators. `flutter test` reste non exécutable à cause du crash Dart/macOS code 134 connu.

## Compilation

`./gradlew assembleDebug` réussi; code Dart et Kotlin compilés; APK debug généré. Avertissement connu: Android Gradle Plugin 7.3 ancien face au compileSdk 34.

## REAL_DEVICE_VALIDATION_REQUIRED

Scénario complet picker→restart→navigation, copie/déplacement/suppression sur stockage interne/SD/USB/cloud, annulation de gros fichiers, conflits provider, partage multi-fichiers, récents après révocation, fluidité gros dossiers.

## Dette technique

Streaming Flutter natif avec progression octet précise; annulation d'un transfert natif déjà lancé; politique « appliquer à tous » interactive par conflit; thumbnails; i18n ARB complète; vérification robuste destination-dans-source pour providers aux identifiants non hiérarchiques.

## Fichiers principaux

`files_controller.dart`, `files_screen.dart`, `file_operation_service.dart`, `destination_picker.dart`, `file_rules.dart`, `SafBridge.kt`, `app_database.dart`, `recents_screen.dart`.

## Statut

**GO LOT 3**, sous réserve des validations appareil explicites. Ne pas commencer le Lot 3 sans accord.
