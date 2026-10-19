# Rapport final — Lot 6.1

## Statut

GO RECETTE 6.1. Le Lot 7 ne doit pas commencer avant la recette sur téléphone réel.

## Corrections livrées

- PDF : matérialisation SAF privée contrôlée, rejet des fichiers vides, diagnostics de durée/taille et erreurs Android détaillées.
- Office : DOCX, XLSX et PPTX reconnus par leur structure OOXML et transmis à une application externe, jamais au navigateur ZIP.
- Performances : suppression des requêtes SQLite N+1 dans les listes; métadonnées enrichies par lot; réglages EPUB sans recréation continue de la WebView.
- Stockage : ouverture automatique du seul emplacement SAF encore autorisé, notamment Téléchargements.
- Récents : invalidation immédiate après une ouverture interne réussie.
- Détails : extension, taille, date et progression visibles en liste.
- Cache : page unique « Stockage et données »; vider le cache conserve progression, signets, favoris et collections. La remise à zéro de progression/historique est une action distincte et confirmée.
- Archives : extraction directement accessible, fil d’Ariane, retour au dossier parent et fiche d’information d’une entrée.
- Paramètres : écran À propos avec version et accès aux licences Flutter.

## Contraintes Android

NexaFiles utilise le Storage Access Framework. Android peut interdire la sélection de la racine `/storage/emulated/0`; l’application ne contourne pas cette protection et n’utilise pas `MANAGE_EXTERNAL_STORAGE`. Elle mémorise et rouvre le meilleur emplacement explicitement autorisé par l’utilisateur.

## Recette téléphone requise

Tester au minimum : un PDF standard et un PDF volumineux depuis Téléchargements; DOCX/XLSX/PPTX avec une application compatible installée; CBR/CBZ et mise à jour des récents; réglages EPUB/BD; cache puis reprise de lecture; réinitialisation séparée de progression; navigation/extraction ZIP.

## Décision

Statut attendu après validation physique : **GO RECETTE 6.1** ou liste ciblée de corrections. Aucun **GO LOT 7** n’est prononcé ici.
