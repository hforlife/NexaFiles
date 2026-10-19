# Architecture des lecteurs — Lot 4

Le flux reste unique : `StorageEntry → ContentSource → FormatDetector → ReaderRegistry → ReaderAdapter → ReaderSession → UI`.

`ReaderRegistry` contient désormais les adapters Comic, PDF, EPUB, texte/Markdown et image. Les sessions ne connaissent pas SAF. Les PDF passent par `MaterializedContentSource`; les autres lecteurs consomment le flux abstrait.

Les locators PDF, EPUB et Comic partagent `reading_progress`. Les signets partagent la table `bookmarks`. Les préférences EPUB et texte globales utilisent `SharedPreferences`; les préférences Comic par livre restent dans `reader_preferences`.

La détection combine signatures, MIME, extension et structure ZIP. Un ZIP n'est déclaré EPUB que si `mimetype` et `META-INF/container.xml` sont présents.
