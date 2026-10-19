# Spike A — Storage Access Framework

## Prototype

`MainActivity.kt` expose un canal Lot 0 pour `ACTION_OPEN_DOCUMENT_TREE`, `takePersistableUriPermission`, liste, métadonnées, lecture, création de dossier/fichier, renommage et suppression. `SafSpike` garde les `content://` opaques. Les copies/déplacements n'ont pas été implémentés: `DocumentsContract.copyDocument/moveDocument` ne sont pas uniformément supportés par les providers; le fallback fiable est flux source → fichier temporaire/destination → validation → suppression source.

## Résultat

- **Validé par inspection/compilation non exécutée**: conception sans conversion URI→path; persistance demandée avec les flags réellement renvoyés par le picker.
- **Non validé sur appareil**: picker, navigation, redémarrage, providers Google Drive/SD/USB, mutations, gros flux et révocation.
- Une permission persistée peut devenir invalide si le document est déplacé ou supprimé; Android l'indique explicitement.
- Android 11+ interdit certains emplacements (`Android/data`, `Android/obb`, racines selon picker). Ne pas demander `MANAGE_EXTERNAL_STORAGE` pour la V1 sans nécessité Play démontrée.

## Abstraction retenue

`ContentSource` couvre le flux séquentiel; `SeekableContentSource` exprime séparément l'accès aléatoire. `StorageRepository` gère arbres, enfants, métadonnées et mutations. Pour un moteur qui exige un fichier/FD seekable, utiliser un des trois ponts: descripteur de fichier conservé ouvert, `SeekableByteChannel` natif, ou copie contrôlée dans le cache privé. Ne jamais inventer un chemin réel depuis une URI.
