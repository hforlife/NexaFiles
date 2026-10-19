# Sécurité des archives

`ArchiveSafetyPolicy` rejette chemins absolus, lecteurs Windows, segments `..`, profondeur, tailles, nombre d'entrées et ratios excessifs. Valeurs initiales: 10 000 entrées, 2 Gio total, 512 Mio par entrée, ratio 200:1, profondeur 32; elles sont configurables et doivent être appliquées avant puis pendant l'extraction, car les métadonnées peuvent mentir.

Règles d'écriture: résoudre chaque cible sous un répertoire privé canonique; créer via fichier temporaire; compter les octets réellement produits; vérifier espace libre avec marge; renommer atomiquement seulement après succès; annulation coopérative; supprimer le temporaire sur toute erreur; quotas par livre/global/LRU; aucun bit exécutable et aucune exécution. Les symlinks/hardlinks sont refusés. Une archive corrompue ne doit jamais invalider un cache antérieur sain.
