# Gestionnaire de fichiers

L'écran Fichiers possède deux niveaux: les racines autorisées persistées dans Drift, puis un navigateur URI basé sur une pile de `StorageEntry`. La pile produit le breadcrumb et gère le retour sans jamais reconstruire de path classique.

Fonctions: racines disponibles/inaccessibles, favoris simples, navigation arbitraire, pull-to-refresh, recherche dans le dossier courant, liste/grille persistée, tri naturel nom/date/taille/type, création, renommage, informations, ouverture externe et sélection multiple.

Le listing utilise uniquement nom/MIME/métadonnées. Les magic bytes ne sont lus qu'à l'ouverture d'un fichier. Les miniatures sont différées afin de ne pas dégrader les gros dossiers.
