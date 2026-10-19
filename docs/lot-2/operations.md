# Opérations

`FileOperationService` orchestre copie, déplacement, suppression multiple, conflits et annulation. Les dossiers sont copiés récursivement via `StorageRepository`; les streams restent sous la responsabilité du pont SAF. Un déplacement supprime la source uniquement après copie complète.

Politiques de conflit: remplacer, conserver les deux, ignorer ou annuler. `Conserver les deux` préserve l'extension. La progression est déterminée par nombre de sources au premier niveau; elle reste volontairement indéterminée avant la première entrée et ne prétend pas mesurer les octets.

L'annulation est vérifiée entre les entrées et pendant les copies pilotées en Dart. Une copie native de fichier déjà engagée n'est pas interruptible avec le MethodChannel actuel. Les destinations partielles créées par le pont sont supprimées sur erreur; la validation appareil doit confirmer chaque provider.
