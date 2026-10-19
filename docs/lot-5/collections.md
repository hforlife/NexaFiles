# Collections et organisation

Les tables `collections` et `collection_items` modélisent une relation plusieurs-à-plusieurs avec `library_items`. Suppression d'une collection : seules ses relations sont supprimées.

Fonctions V1 : création, renommage, suppression, ajout et retrait d'un contenu. Favoris et vues En cours/Terminés sont des filtres système, pas des collections automatiques stockées.

Les statuts Non commencé, En cours et Terminé sont dérivés de la progression, avec surcharge manuelle légère.
