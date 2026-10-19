# LOT 4.1 — CORRECTIONS

## EPUB

Rendu XHTML/CSS/images via Android WebView locale, TOC/spine, recherche, signets, personnalisation, métadonnées et couverture.

## Moteur EPUB final

Adaptateur EPUB NexaFiles + WebView Android restreinte. Les ressources sont extraites dans le cache privé avec contrôle de traversal. Aucun script du livre ni accès réseau n'est autorisé.

## CFI / progression

Locator stable par `href` du spine avec index de chapitre en secours. Ce n'est pas un CFI standard. Les anciens locators `chapter:N` sont acceptés puis remplacés au prochain enregistrement.

## PDF

`PdfRenderer` reste le moteur de rendu paresseux. Progression, reprise, zoom, navigation et signets sont conservés.

## Recherche PDF

`PdfBox-Android 2.0.27.0` extrait la couche texte page par page hors ligne. La recherche retourne page et extrait, puis navigue au résultat. Un scan sans texte affiche un état propre ; aucun OCR.

## Couvertures

EPUB : image déclarée `cover-image` ou métadonnée `cover`, réduite à 300 px. PDF : première page rendue à 300 px. Les deux sont générées sans bloquer la navigation et stockées dans `CacheManager/covers`.

## Navigation images

Images voisines du dossier triées naturellement, navigation par swipe, chargement paresseux et éviction au-delà des voisines immédiates.

## Compilation

`./gradlew assembleDebug` : **SUCCÈS** le 2 octobre 2026. APK debug généré.

## REAL_DEVICE_VALIDATION_REQUIRED

Gros PDF, PDF complexes, avec/sans couche texte, EPUB CSS complexe/volumineux/polices embarquées, reprise par href, WebView, gestes, images haute résolution, RAM et fluidité.

## Limitations restantes acceptées pour V1

- locator EPUB par href et chapitre, pas de CFI standard ni position intra-chapitre ;
- liens externes EPUB bloqués au lieu d'être ouverts après confirmation ;
- PDF protégés, OCR et double page PDF non pris en charge ;
- DRM EPUB non pris en charge.

## Statut

**GO LOT 5**
