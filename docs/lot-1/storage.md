# Stockage et SAF

`StorageRepository` expose des URI opaques, des capacités et des `ContentSource`. `SafStorageRepository` traduit les appels Flutter vers `SafBridge.kt`; aucun `content://` n'est transformé en chemin.

Le pont gère picker, grants persistants, liste, métadonnées, lecture, création, renommage, suppression, copie et déplacement de fichiers. La copie est transactionnelle au mieux: destination créée, flux copié, destination supprimée sur échec, puis source supprimée pour un déplacement. La copie récursive de dossiers est volontairement différée.

`REAL_DEVICE_VALIDATION_REQUIRED`: persistance après redémarrage, providers locaux/cloud/SD/USB, révocation, gros flux, collision de noms et opérations inter-provider.
