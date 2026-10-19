# Lecteur Manga/BD — Lot 3

Le lecteur propose :

- page simple, défilement vertical et double page ;
- lecture gauche-vers-droite ou droite-vers-gauche ;
- ajustement largeur, hauteur ou zoom libre ;
- zoom/panoramique avec `InteractiveViewer` ;
- contrôles immersifs masquables, curseur et navigation rapide ;
- couverture seule en mode double page ;
- reprise à la dernière page et sauvegarde temporisée de la progression ;
- préférences globales dans `SharedPreferences` et préférences par livre dans SQLite ;
- section « Continuer la lecture » dans Bibliothèque.

La progression est enregistrée après stabilisation du changement de page et lors de la fermeture du lecteur. La base est migrée en version 3 avec une table `reader_preferences`.

À valider sur appareil réel : gestes concurrents page/zoom, RTL dans les trois modes, restauration après arrêt forcé, comportement des barres système et fluidité sur grands albums.
