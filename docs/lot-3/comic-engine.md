# Moteur Manga/BD — Lot 3

Le moteur BD réutilise `ArchiveRegistry`. `ComicReaderAdapter` transforme une session d'archive en `ArchiveComicPageSource`, trie naturellement les images (`2.jpg` avant `10.jpg`) et charge les pages à la demande.

La détection applique les règles suivantes :

- `.cbz`, `.cbr` et `.cb7` indiquent directement un contenu BD lorsque la signature du conteneur concorde ;
- un ZIP ordinaire devient une BD s'il contient au moins cinq images et si celles-ci représentent au moins 70 % des fichiers utiles ;
- `ComicInfo.xml`, fichiers cachés et métadonnées macOS ne diluent pas ce ratio.

Le cache mémoire est borné à quatre pages. Le lecteur précharge la page précédente, la page courante et les deux suivantes. Les couvertures sont générées depuis la première page, réduites à 300 px de large, écrites dans le cache privé puis référencées en base.

Limites V1 : JPEG, PNG et WebP uniquement ; pas de GIF animé, AVIF, TIFF, PDF encapsulé ou dossier d'images ouvert directement depuis l'écran Fichiers.
