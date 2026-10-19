# Texte, Markdown et images — Lot 4

TXT est décodé en UTF-8 avec remplacement des séquences invalides. Le lecteur propose défilement, sélection, recherche, taille et thème, avec progression. L'implémentation charge le fichier en mémoire : les très gros TXT restent à valider et devront passer à un découpage par blocs.

Markdown prend en charge un rendu texte sécurisé des éléments courants. Les balises HTML sont retirées et aucun contenu actif n'est exécuté. La V1 ne prétend pas couvrir toutes les extensions Markdown.

Le lecteur image interne accepte JPEG, PNG, WebP et GIF reconnus par Flutter, avec fond sombre, zoom, pan et double tap. Depuis un dossier, les images sont naturellement triées, navigables par swipe et chargées paresseusement autour de l'image courante.
