# Moteur d'archives — Lot 3

## Architecture

`ArchiveRegistry` sélectionne un `ArchiveAdapter` à partir du format détecté. Une session expose la liste des entrées et ouvre une entrée à la demande sous forme de `ContentSource`. L'interface ne dépend donc ni d'un chemin local ni de l'UI.

| Format | Implémentation | Lecture/liste | Extraction | Création |
|---|---|---:|---:|---:|
| ZIP / CBZ | package Dart `archive` | oui | oui | non |
| RAR / CBR | Junrar 7.5.8, pont Kotlin | oui | oui | non |
| 7Z / CB7 | Commons Compress 1.26.2 + XZ 1.9, pont Kotlin | oui | oui | non |

Les URI SAF sont matérialisées dans le cache privé pour les bibliothèques natives qui exigent un fichier seekable. Une seule entrée est renvoyée à la fois. Le navigateur construit une arborescence virtuelle, permet l'extraction complète ou ciblée, affiche la progression et accepte une annulation coopérative.

## Limites V1

- Archives protégées par mot de passe : non prises en charge, avec erreur contrôlée du moteur.
- Archives multi-volumes : non garanties.
- 7Z solide : lisible, mais chaque accès peut reparcourir l'archive matérialisée ; les performances doivent être mesurées sur appareil.
- Pas de création ni de modification d'archive.
- En cas de conflit de nom à l'extraction, le fournisseur SAF décide du nom final ; une politique remplacer/renommer explicite reste une dette.
- Le cache matérialisé est privé à l'application et réutilisé par URI pendant la session applicative.

## Validation

`assembleDebug` réussit. La lecture effective de corpus ZIP/RAR/7Z via plusieurs fournisseurs SAF reste une recette sur appareil réel.
