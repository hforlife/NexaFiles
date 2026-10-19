# Architecture du socle V1

Architecture feature-first pragmatique:

- `app`: bootstrap, router, thème et i18n;
- `core`: stockage, formats, lecteurs, archives, comics, cache, base, erreurs et plateforme;
- `features`: écrans et état propres à Fichiers, Bibliothèque, Récents, Outils et Paramètres;
- `shared`: widgets réellement partagés.

Riverpod sert à l'injection et aux états asynchrones d'écran. La logique métier reste dans les repositories/services. Le router centralise les routes actuelles et réserve `/file`, `/reader/pdf`, `/reader/epub`, `/reader/comic` et `/archive` sans prétendre fournir ces lecteurs.

Le code `lib/lot0` et `spikes` reste historique. Le code V1 n'en dépend pas.
