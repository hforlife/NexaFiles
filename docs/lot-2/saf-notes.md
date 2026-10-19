# Notes SAF

- Les URI `content://` restent opaques.
- Les racines métier sont stockées en base, puis rapprochées des grants Android au démarrage.
- Une racine sans grant valide apparaît comme inaccessible et peut être retirée ou réautorisée.
- Copie/déplacement utilisent des flux lorsque le provider ne fournit pas d'opération native fiable.
- Partage: `ACTION_SEND`/`ACTION_SEND_MULTIPLE`, `ClipData` et grant de lecture.
- Ouvrir avec: `ACTION_VIEW` avec MIME et grant de lecture.

`REAL_DEVICE_VALIDATION_REQUIRED`: Documents/Download, SD, USB, cloud, redémarrage, grants révoqués, collisions propres aux providers, gros fichiers, suppression récursive et intents multi-partage.
