# PDF — Lot 4

Le rendu reste assuré par `android.graphics.pdf.PdfRenderer`. Une URI SAF est matérialisée dans le cache privé, puis le pont Kotlin expose le nombre de pages et un rendu PNG paresseux. Une seule page est rendue à la demande.

La recherche hybride utilise `PdfBox-Android 2.0.27.0` (Apache-2.0) : extraction Unicode page par page, résultats avec extrait et navigation vers la page. Un scan sans couche texte retourne proprement aucun texte recherchable ; aucun OCR n'est lancé.

Le lecteur fournit défilement vertical, page unique, zoom/pan, navigation rapide, numéro de page, signets, progression temporisée et reprise par `PdfLocator`.

Une miniature de la première page est générée paresseusement à 300 px dans `CacheManager/covers`. Limites V1 : table des matières, double page et mot de passe non disponibles. Les PDF invalides produisent un message applicatif générique.
