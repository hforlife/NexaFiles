# LOT 6.4 — FINAL REPORT

## Home / Continue Reading

La Home affiche le dernier document possédant une progression (PDF, EPUB, comic, texte ou Markdown), sans carte vide. La donnée provient d'une requête SQLite dédiée, sans scan du stockage. L'action repasse par le `ReaderRegistry` canonique et les lecteurs restaurent leur progression enregistrée.

## Locations

La Home ne crée plus de carte permanente « Autoriser l'accès ». Le bouton `+` est l'unique entrée globale d'ajout. Les emplacements persistés accessibles sont affichés avec leur capacité quand Android la fournit; un emplacement enregistré devenu inaccessible reste identifiable comme « Accès perdu ».

## Remove location

« Retirer de NexaFiles » supprime la référence locale puis libère la permission SAF persistée lorsque possible. La confirmation précise que le dossier et ses fichiers restent sur l'appareil. Aucun appel de suppression physique n'est effectué.

## Directory performance

**Root cause :** enrichissement et génération de previews/couvertures, requêtes de progression unitaires et construction non lazy pouvaient faire croître le coût avec le nombre d'entrées.

**Before :** aucune mesure automatique comparable 0/10/100/500 fichiers n'était disponible dans cet environnement.

**After :** premier affichage basé sur les entrées SAF basiques, métadonnées DB chargées en lot, `ListView.builder` / `GridView.builder`, miniatures demandées seulement par les cellules construites, cache mémoire borné et file de couvertures séquentielle. Les traces `[PERF]` couvrent la liste SAF, le premier rendu, la DB et le routage de format.

Les mesures chiffrées 10/100/500 fichiers n'ont pas pu être obtenues automatiquement faute d'appareil Android connecté; elles ne sont pas inventées et font partie de la recette téléphone.

## Library removal

Un élément peut être retiré de la Bibliothèque après confirmation sans supprimer son fichier physique. Une source peut également être retirée de l'indexation. La suppression du téléphone reste une action séparée du gestionnaire de fichiers.

## Covers

PDF, EPUB et CBZ/CBR/CB7 sont mis en file pour produire leur couverture pendant l'indexation, sans ouverture préalable. Le cache de couverture est partagé via la base entre Bibliothèque, Fichiers, Récents et Continuer la lecture. Une icône de format est toujours utilisée en repli.

## Image previews

Les images, vidéos et artworks audio disponibles utilisent `ContentResolver.loadThumbnail` (décodage Android échantillonné) et un cache mémoire LRU borné. L'image originale pleine résolution n'est pas chargée pour une tuile.

## Hidden files

La préférence « Afficher les fichiers cachés » filtre immédiatement fichiers et dossiers dont le nom commence par un point. Aucun nouveau scan SAF n'est déclenché.

## Audio

Classification canonique MIME/extension, adaptateur du `ReaderRegistry`, initialisation paresseuse de `MediaPlayer`, lecture/pause, seek, temps courant/durée, volume système et commandes précédent/suivant lorsqu'une playlist est fournie. L'élément ouvert est enregistré dans Récents. Les codecs réellement disponibles dépendent d'Android.

## Video

Classification canonique, adaptateur du `ReaderRegistry`, `VideoView` Android paresseux avec contrôleur natif (lecture/pause/seek/durée), plein écran immersif et orientation paysage. Les codecs dépendent du terminal Android; « Ouvrir avec… » reste disponible depuis le menu fichier.

## Trash

Sur une source SAF compatible, un fichier est déplacé dans `.NexaTrash` sous la racine autorisée. NexaFiles conserve nom, URI parent d'origine, URI de corbeille, date et taille. Outils > Corbeille permet restauration, suppression définitive et vidage avec confirmations. Un conflit de restauration produit un nom « (2) », donc ne remplace jamais silencieusement. Si le déplacement n'est pas garanti, une deuxième confirmation propose explicitement la suppression définitive. Les dossiers restent pour l'instant dans ce fallback explicite.

## Navigation

Navigation globale unique conservée : Fichiers, Bibliothèque, Récents, Outils. Aucun Drawer global. La Corbeille a été ajoutée aux vrais outils.

## Performance

Les moteurs média ne sont pas initialisés au démarrage. Le tri repose sur les entrées basiques. Les listes sont virtualisées et les previews sont chargées à la demande. La génération de couvertures de bibliothèque est sérialisée afin d'éviter une tâche lourde simultanée par fichier.

## Tests

- `testDebugUnitTest` : succès.
- Tests ajoutés : classification audio/vidéo et sérialisation des métadonnées de corbeille.
- Compilation Flutter debug/release : succès via Gradle.
- Les tests Flutter directs ne sont pas exécutables sur cet hôte à cause du crash connu du runtime Flutter macOS (`cpuinfo_macos.cc:42`); la compilation Dart complète a néanmoins été validée par les tâches Flutter Gradle.

## Debug build

`assembleDebug` : succès. APK : `build/app/outputs/flutter-apk/app-debug.apk`.

## Release build

`assembleRelease` : succès. APK : `build/app/outputs/flutter-apk/app-release.apk`. R8 signale les classes optionnelles déjà connues de PDFBox/Commons Compress/SLF4J, sans échec de build.

## REAL_DEVICE_VALIDATION_REQUIRED

Valider sur téléphone : temps d'ouverture des dossiers 0/20/100/500 éléments, génération visuelle des couvertures jamais ouvertes, codecs audio/vidéo propres au terminal, plein écran vidéo, persistance SAF après redémarrage, restauration et fallback définitif de la corbeille. Les temps réels doivent être relevés depuis les traces `[PERF]`.

## Known limitations

- Les métadonnées audio détaillées (artiste/album) ne sont affichées que si le thumbnail système est disponible; le lecteur montre sinon le nom du fichier.
- Précédent/suivant est prévu par le lecteur, mais une ouverture isolée depuis Récents ne fournit volontairement qu'une piste.
- La corbeille garantit actuellement le déplacement/restauration des fichiers; les dossiers utilisent le fallback clairement annoncé.
- Aucune mesure de performance sur stockage réel n'a été fabriquée en l'absence d'appareil connecté.

## Status

**GO RECETTE 6.4**

Le Lot 7 n'est pas commencé. Le passage au Lot 7 dépend de la recette sur téléphone réel.
