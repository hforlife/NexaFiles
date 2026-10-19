# Sécurité des archives — Lot 3

La politique est exécutée avant lecture ou extraction :

| Contrôle | Limite V1 |
|---|---:|
| Nombre d'entrées | 10 000 |
| Taille totale décompressée | 2 Gio |
| Taille d'une entrée | 512 Mio |
| Ratio de compression | 200:1 |
| Profondeur de chemin | 32 |

Sont rejetés : chemins absolus Unix, chemins absolus Windows, segments `..`, tailles négatives, entrée non vide annoncée à zéro octet compressé, dépassements de taille et espace disponible insuffisant lorsqu'il est connu.

L'extraction crée les fichiers exclusivement via le répertoire SAF choisi. En cas d'erreur, les URI créées pendant l'opération sont supprimées dans la mesure permise par le fournisseur. L'annulation est coopérative entre deux entrées.

Point connu : Commons Compress n'expose pas simplement la taille compressée par entrée 7Z dans le chemin API utilisé ; le pont renseigne une valeur conservatrice. Les limites de nombre, taille, profondeur et total restent actives, mais le ratio 7Z doit être renforcé dans une version suivante.
