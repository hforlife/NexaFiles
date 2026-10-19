# LOT 6.3 — Rapport final

## Directory performance

**Root cause:** les informations Bibliothèque étaient auparavant recherchées fichier par fichier et pouvaient retarder/reconstruire la liste. Les enrichissements n’étaient pas clairement séparés du résultat SAF initial.

**Correction:** la navigation est publiée immédiatement, `listChildren` reste sur le pool I/O Android, les entrées SAF basiques sont affichées avant l’enrichissement SQLite groupé. La détection profonde reste réservée à l’ouverture. Les traces `[PERF]` existantes mesurent `listChildren` et le premier paint.

**Perf:** les mesures chiffrées dépendent du provider SAF et doivent être collectées sur le téléphone de recette.

## Storage primary

**Android limitation:** le Storage Access Framework peut interdire la sélection de la racine `/storage/emulated/0` sur les versions Android récentes. NexaFiles n’ajoute pas `MANAGE_EXTERNAL_STORAGE` et ne prétend pas disposer d’un accès non accordé.

**Implementation:** découverte des volumes avec `StorageManager`; affichage permanent de « Stockage principal » et de la carte SD éventuelle. Sans permission, la carte indique « Autoriser l’accès » et ouvre le sélecteur SAF. Téléchargements reste un emplacement séparé.

## Location card

La carte suit désormais une composition verticale : icône, titre, capacité ou état. Les textes sont bornés et utilisent une ellipse.

## Reader preferences latency

**Root cause:** certaines options attendaient la persistance ou reconstruisaient la vue de lecture.

**Correction:** état visuel Comic mis à jour avant l’écriture DB, écriture asynchrone, trace `[PERF] reader preference visual update`. Le réglage EPUB évite déjà les reconstructions continues introduites avant 6.3.

## Page navigation latency

**Root cause:** rendu PDF demandé à la navigation et cache sans borne claire; pages Comic voisines pas toujours exploitées par les commandes.

**Correction:** cache PDF LRU borné à cinq rendus, cache Comic borné, préchargement autour de la page et progression sauvegardée avec debounce indépendamment de l’affichage.

## Cancellation

**Root cause:** les dialogues donnaient peu de retour et certains appels SAF natifs restent atomiques au niveau du provider.

**Correction:** fermeture UI immédiate au tap Annuler; les boucles Dart de scan et d’extraction vérifient leur token entre dossiers, entrées et chunks. Un `copyTo` déjà engagé par un provider Android peut rester non interruptible jusqu’au retour de ce provider.

## Double page

Fonction centrale `pageStepForMode`: page unique = 1, double-page = 2. Les boutons précédent/suivant utilisent ce pas, avec bornes; le slider conserve le ciblage exact.

## Zoom

Image Viewer et Comic prennent en charge pinch, pan, double-tap et reset par double-tap, avec une limite de zoom bornée.

## Library sorting

**Root cause:** le changement lançait un nouveau `Future` dans `build`, pouvant afficher un résultat précédent ou un chargement intermédiaire.

**Correction:** filtre et tri synchrones sur le snapshot déjà chargé. Modes exposés réellement : titre A–Z, titre Z–A, récemment ajouté, récemment ouvert et progression.

## Recent routing

**Root cause:** un tap Recent appelait systématiquement l’application externe.

**Correction:** URI relue, détection canonique par signature/MIME/nom, validation du type sauvegardé puis ouverture par `ReaderRegistry`. Un fichier absent ou modifié produit un message explicite.

## Cover generation

Le scanner programme les couvertures PDF, EPUB et Comic dans une file séquentielle. Les fichiers inchangés mais sans couverture sont également programmés. Cette génération ne bloque pas la liste ni le scan visible.

## Image thumbnails

Les JPG/PNG/WebP visibles utilisent `ContentResolver.loadThumbnail` avec décodage échantillonné 240×240 et orientation gérée par Android. Le cache mémoire est borné à 32 miniatures et un placeholder de format reste toujours visible.

## Navigation

Le Drawer a été supprimé. La Bottom Navigation reste l’unique navigation globale smartphone. Back et breadcrumb assurent la navigation contextuelle des fichiers.

## Hidden files

Option persistante « Afficher les fichiers cachés », OFF par défaut. Le filtre `.nom` s’applique à la liste déjà chargée sans nouveau scan.

## Tests

- Tests Android Gradle : réussis.
- Tests Dart ajoutés : pas double-page ±2, page simple +1, bornes et règle des fichiers cachés.
- L’exécution directe `flutter test` reste empêchée sur cette machine par le crash connu du runtime Dart macOS `cpuinfo_macos.cc:42`; la compilation Flutter via Gradle est réussie.

## Debug build

`assembleDebug` : réussi.

## Release build

`assembleRelease` : réussi. Les avertissements R8 existants concernent des codecs/classes optionnels de PDFBox/Commons Compress.

## REAL_DEVICE_VALIDATION_REQUIRED

Mesurer sur téléphone : démarrage, Téléchargements, gros dossier, première page et page préchargée Comic/PDF, fit, annulation et relance. Vérifier également la politique du sélecteur SAF du constructeur concernant la racine du stockage principal.

## Status

**GO RECETTE 6.3**

Le Lot 7 reste suspendu jusqu’à la recette physique.
