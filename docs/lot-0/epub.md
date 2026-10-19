# Spike C — EPUB

## Candidats

- `flutter_epub_viewer` 2.0.0: Epub.js dans InAppWebView; CFI, recherche, thèmes, sélection et mise en page riche. C'est le candidat V1 car un CFI reste sémantique lors d'un reflow.
- `epub_view` 3.3.0 / `epubx`: rendu Flutter HTML, plus simple et multiplateforme, mais la reprise fondée sur index/scroll est moins stable après changement de police ou largeur.

## Décision provisoire

Retenir Epub.js/WebView si les tests confirment: restauration au même CFI après variations taille/police/marges, CSP/accès réseau bloqué, polices embarquées, liens internes, gros EPUB et temps de reprise acceptable. Désactiver JavaScript non requis hors runtime packagé, intercepter la navigation, refuser `file://` arbitraire et tout téléchargement.

Les deux prototypes ne sont pas compilés à cause du SDK local défaillant. Table des matières, recherche, thèmes, images/CSS, polices et CFI sont **annoncés par les moteurs mais NON VALIDÉS ici**.
