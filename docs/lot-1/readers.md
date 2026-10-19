# Readers, archives et comics

Le flux prévu est `ContentSource → FormatDetector → ReaderRegistry → ReaderAdapter → ReaderSession`. Aucun moteur PDF/EPUB complet n'est inclus au Lot 1.

`FormatDetector` conserve séparément conteneur et contenu. Il reconnaît signatures PDF/ZIP/RAR/7Z/images et inspecte facultativement les entrées ZIP pour EPUB ou comic probable.

`ArchiveRegistry` impose `ArchiveSafetyPolicy` aux adapters. `ComicPageSource` possède deux implémentations initiales: dossier SAF et ZIP/CBZ. Le ZIP utilise chargement paresseux, tri naturel et cache LRU borné. RAR et 7Z restent des adapters futurs.

`REAL_DEVICE_VALIDATION_REQUIRED`: fichiers volumineux, archives corrompues/solides, RAM, annulation et lecteurs natifs.
