# LOT 6 — RAPPORT FINAL

## Direction UX

Efficacité des gestionnaires classiques, hiérarchie Material 3 et priorité aux actions quotidiennes visibles.

## Accueil Fichiers / Accès rapides

Cartes d'emplacements SAF responsives et raccourcis réels vers Récents, Bibliothèque, favoris et racines reconnues. Aucune capacité distante fictive.

## Explorateur / Liste / Grille

Recherche, affichage et tri dans l'AppBar. Breadcrumb conservé. Lignes enrichies par date, taille, couverture et progression en cache ; grille responsive adaptée aux couvertures.

## Sélection / Actions

Appui long avec haptique, sélection multiple, Tout sélectionner et barre inférieure Copier/Déplacer/Partager/Supprimer.

## Bibliothèque / Continuer / Collections

Accueil visuel du Lot 5 conservé : Continuer, Récemment ajoutés, grille dense, recherche, filtres, tris, collections et fiches détaillées.

## Récents

Section explicitement nommée « Fichiers ouverts récemment ».

## Outils

Grille d'actions réellement disponibles : Archives, nettoyage du cache, dossiers de bibliothèque et emplacements SAF.

## Comic / PDF / EPUB / Image / Texte

Contrôles essentiels directement visibles, immersion conservée et aucune régression du moteur de lecture.

## Design System / Light / Dark

Tokens centralisés, identité vert minéral, surfaces hiérarchisées, rayons cohérents et couleurs sémantiques limitées.

## Accessibilité

Composants Material à cibles standard, tooltips, semantics sur les accès rapides, contraste issu du ColorScheme et support du text scaling à valider sur appareil.

## Performance perçue

IndexedStack conserve les onglets. Les couvertures de l'explorateur sont uniquement lues depuis le cache et décodées à résolution bornée. Les actions structurantes répondent immédiatement.

## i18n

Navigation principale et paramètres restent FR/EN. Une centralisation complète des chaînes fonctionnelles ajoutées dans les lots successifs demeure une dette avant diffusion internationale.

## Compilation

`./gradlew assembleDebug` : **SUCCÈS** le 2 octobre 2026. APK debug généré.

## Tests réellement exécutés

La VM Dart autonome reste bloquée par `cpuinfo_macos.cc:42`. Aucun test n'a été supprimé. La compilation Gradle vérifie les sources Flutter/Kotlin.

## REAL_DEVICE_VALIDATION_REQUIRED

Ergonomie tactile, navigation, gestures, sélection, haptics, light/dark, orientation, petits/grands écrans, scroll bibliothèque, grilles, performances explorer, couvertures, clavier, system bars et readers.

## Dette UI restante

Centralisation i18n complète, raccourcis personnalisables, aperçu de couvertures dans les cartes Collection et optimisation tablette dédiée.

## Statut

**GO LOT 7**
