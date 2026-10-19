# Base locale

Drift 2.15 pilote SQLite via une connexion différée dans le dossier applicatif. La version initiale crée uniquement les tables utiles au socle:

- `library_items`;
- `reading_progress`, avec locator JSON extensible;
- `bookmarks`;
- `recent_items`;
- `library_roots`.

Collections, favoris et préférences lecteur seront ajoutés par migration lorsqu'un cas d'usage réel les consommera. Les fichiers et couvertures ne sont jamais stockés dans SQLite. `PRAGMA foreign_keys` est activé à chaque ouverture.
