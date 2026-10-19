# Audit UX — Lot 6

| Parcours fréquent | Résultat conceptuel |
|---|---:|
| Ouvrir un emplacement | 1 interaction |
| Téléchargements autorisé comme racine | 1 interaction |
| Recherche dans un dossier | 1 interaction |
| Liste / grille | 1 interaction |
| Tri | 1 à 2 interactions |
| Reprendre une lecture | 2 interactions maximum depuis la navigation principale |
| Partager une sélection | appui long + action directe |
| Informations fichier | menu contextuel en 2 interactions |
| Ajouter à une collection | fiche + action collection |

La navigation principale conserve l'état via `IndexedStack`; le contrôleur Fichiers conserve dossier, recherche et mode d'affichage. Aucun bouton Cloud/FTP/SMB fictif n'a été ajouté.

Points à valider sur appareil : densité avec grands textes, clavier de recherche, scroll des grilles, contraste réel OLED, gestes concurrents dans les lecteurs et barres système.
