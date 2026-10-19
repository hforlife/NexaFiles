# Spike B — PDF

## Comparaison et décision provisoire

`pdfrx` est prioritaire: PDFium homogène, viewer continu/page unique, zoom, navigation, texte/recherche et mot de passe. `pdfx` utilise `PdfRenderer` Android et constitue le repli plus léger, mais ses capacités textuelles sont insuffisantes pour l'objectif recherche. Les deux sont sous licence MIT au niveau plugin; PDFium est BSD-3-Clause avec notices tierces.

## État expérimental

Le prototype exécutable n'a pas pu être construit: le SDK Flutter local plante avant `pub get`, aucun appareil n'est connecté et aucun corpus PDF n'a été fourni. Ouverture SAF, première page, gros PDF, PDF image, malformé et chiffré sont donc **NON VALIDÉS**. Aucune mesure n'est inventée. Après upgrade Flutter, créer deux flavors de spike avec le même corpus et des marqueurs `Timeline`, `adb shell dumpsys meminfo` et 10 répétitions cold/warm. La sélection finale de `pdfrx` reste conditionnelle à ce test.
