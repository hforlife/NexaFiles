# Spikes D/E/F — archives et comics

## ZIP / CBZ

Le prototype `ZipComicPageSource` indexe l'archive, filtre JPG/PNG/WebP, trie naturellement et décompresse à la demande dans un LRU borné (3 pages par défaut). Il n'extrait rien sur disque. Le tri `1, 2, 10`, les signatures et les garde-fous ont des tests écrits, mais non exécutables tant que Flutter plante. La sémantique réellement lazy de `archive` et le pic mémoire doivent être profilés sur 20/200/500 pages après migration vers `archive` 4.x.

## RAR / CBR

Choix à tester: `junrar` Java/Apache-2.0, en exigeant corpus RAR4, RAR5, solide, chiffré et corrompu. Pour une archive solide, une page tardive dépend du bloc précédent: accès aléatoire réellement constant impossible. Le backend extraira séquentiellement vers un cache privé borné/annulable. UnRAR/7-Zip JNI reste un dernier recours soumis à revue licence.

## 7Z / CB7

Choix à tester: Apache Commons Compress avec `SevenZFile`/`SeekableByteChannel` (Apache-2.0). Une URI SAF doit être adaptée en canal seekable ou copiée au cache. Les archives solides imposent lecture séquentielle et cache temporaire; l'abstraction `ComicPageSource` masque cette différence. Commons Compress documente une couverture incomplète de certains codecs/filtres 7z.

RAR/7Z ne sont **pas validés expérimentalement**: aucun binaire/corpus ni appareil n'est présent.
