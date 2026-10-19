# Scanner de bibliothèque

Les racines d'indexation SAF sont séparées des emplacements du gestionnaire dans `library_scan_roots`. Aucun scan agressif n'est lancé au démarrage : ajout d'une racine ou actualisation manuelle uniquement.

`LibraryScanner` parcourt les dossiers séquentiellement, sans `Future.wait`, et publie fichier courant, nombre analysé et erreurs. L'annulation est coopérative. Une erreur de dossier ou fichier est isolée.

PDF, EPUB, CBZ, CBR, CB7, TXT et Markdown sont indexables. L'incrément repose sur URI, taille et date de modification. Un élément inchangé n'est pas reparsé. EPUB fournit titre et auteur ; les autres formats utilisent le nom sans extension. Les URI absentes après un scan achevé sont marquées indisponibles sans effacer progression ou signets.

Limite V1 : une annulation avant la fin ne synchronise pas les éléments disparus, volontairement afin d'éviter les faux retraits.
