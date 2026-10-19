# Lot 6.2 — Rapport final

## PDF root cause

Le pipeline couverture et le pipeline lecteur appelaient le même `PdfRenderer`, ce qui excluait l'accès SAF comme cause principale puisque la couverture était valide. Le chemin lecteur ne validait toutefois ni le PNG reçu ni son décodage, ne journalisait aucune dimension et confiait au widget une image sans contrainte d'affichage explicite. En parallèle, rendu et recherche PDF étaient exécutés depuis le handler principal Android. Enfin, le rendu reposait sur la transformation implicite de `PdfRenderer`, malgré un bitmap cible agrandi.

## PDF correction

- matérialisation validée (`exists`, taille, chemin) et journalisée ;
- `PdfRenderer`, `openPage` et compression exécutés sur un executor natif dédié ;
- matrice de mise à l'échelle explicite vers le bitmap cible et fond blanc conservé ;
- diagnostics debug : page count/index, tailles page/bitmap, durée, taille PNG, état non vide et réception widget ;
- décodage Flutter contrôlé avant affichage, surface contrainte avec `SizedBox.expand` ;
- cache commun `PdfReaderSession.render(page, width)` utilisé par couverture et lecteur ;
- aucune inversion/recoloration du bitmap en thème sombre.

Le contrôle élémentaire « render page 0 → decode → display raw bitmap » est désormais le chemin même du composant `_PdfPage`; il ne nécessite donc aucun écran debug à conserver en release.

## Format detection root cause

Après inspection d'un ZIP, le résultat raffiné n'était repris que pour `comic` et `epub`. Un OOXML correctement identifié tombait donc quand même dans `ArchiveBrowserScreen`. De plus, APK n'avait pas de type sémantique dédié.

## APK

`ContentKind.apk` a été ajouté. Extension, MIME et structure ZIP minimale (`AndroidManifest.xml` avec `resources.arsc` ou `classes*.dex`) sont reconnus. L'action principale utilise l'intent Android externe avec le MIME package Android ; APK n'est jamais envoyé à l'explorateur ZIP.

## OOXML

DOCX, XLSX et PPTX sont classés avant la décision de handler, par extension ou structure `[Content_Types].xml` + répertoire métier. Ils utilisent « Ouvrir avec… » et ne passent plus par le lecteur d'archives.

## Performance root causes

- `SAF read` chargeait le fichier complet pour obtenir 16 octets de signature lors d'un tap ;
- `DocumentFile.listFiles`, lecture SAF, matérialisation/indexation archive et rendu/recherche PDF étaient lancés sur le thread du channel Android ;
- couverture PDF pouvait refaire le rendu demandé par le lecteur ;
- l'accueil ouvrait automatiquement l'unique racine, empêchant un home rapide et stable.

Corrections : `readPrefix` borné (32 octets), executors I/O SAF/archive/PDF, cache de rendu PDF, couvertures lancées sans bloquer la navigation et accueil rendu immédiatement sans scan automatique.

## Mesures avant/après

Les mesures téléphone ne sont pas inventées : elles doivent être collectées pendant la recette 6.2. Les marqueurs debug `[PERF]` couvrent maintenant `SAF listChildren`, métadonnées, préfixe de détection, matérialisation/indexation archive, ouverture/rendu PDF, détection/routage et premier frame du dossier. Le changement déterministe est : détection avant = lecture de tout le fichier ; après = 32 octets.

## Directory first paint

Le listing natif ne bloque plus le thread UI. Les entrées SAF de base sont publiées dès retour de `listChildren`; la requête DB de progression/couverture reste dans un `FutureBuilder` postérieur à la liste initiale. Un marqueur de premier frame est émis en debug.

## Reader setting latency

Les réglages BD restent persistés après mise à jour visuelle. Le lot déplace surtout les opérations PDF/archive hors UI ; les valeurs réelles sur téléphone sont à relever pendant la recette.

## List metadata

Le mode liste utilise une tuile structurée avec nom sur deux lignes, type, taille, date SAF et progression séparée. Taille/type/date ne dépendent pas de l'historique ou de la bibliothèque. Les dossiers n'entraînent aucun comptage coûteux.

## Recent covers

La requête Récents rejoint désormais `cover_cache_key` et `reading_progress`. Elle réutilise le fichier de couverture commun et fournit des fallbacks par type. Les dates sont présentées comme « À l'instant », « Il y a N min », « Aujourd'hui » ou « Hier ».

## Reader +/- navigation

PDF et Comic affichent `−  page / total  +` avec un saut exactement d'une page, en complément du slider. Le `PageView.reverse` existant continue d'assurer le RTL des comics sans inverser la notion précédente/suivante.

## File Manager+ inspired Home

Le Home conserve uniquement les emplacements SAF réellement accordés, des cartes compactes et les accès rapides disponibles. L'ouverture automatique de la seule racine a été supprimée. Aucun faux stockage, cloud, FTP/SMB ou scan global n'a été ajouté.

## Navigation

Un Drawer Material 3 est accessible depuis l'accueil Fichiers et expose les racines réelles, Favoris, Bibliothèque, Récents et Paramètres. Dans un dossier, une flèche retour, le breadcrumb, recherche, vue, tri et menu restent disponibles. L'engrenage redondant a été retiré de l'app bar Fichiers.

## Build

- `testDebugUnitTest`: SUCCESS
- `assembleDebug`: SUCCESS
- `assembleRelease`: SUCCESS
- APK release : `build/app/outputs/flutter-apk/app-release.apk`
- SHA-256 : `8aea6f08d25e6e221621230c03d1f22a733f0ba0b1be685677ce75a9aa84f2aa`

## Tests

Fixtures légères ajoutées pour ZIP, APK, DOCX, XLSX, PPTX, EPUB, CBZ, APK structurel et priorité de la signature PDF. La compilation Flutter via Gradle et les tests Android passent. L'exécution directe de `flutter test` reste bloquée sur cette machine par le crash connu du runtime Dart macOS (`cpuinfo_macos.cc:42`), indépendamment du code applicatif.

## REAL_DEVICE_VALIDATION_REQUIRED

Obligatoire : PDF rendu et navigation, CBZ/CBR +/−, ouverture externe OOXML, installation/ouverture APK, ZIP interne, couvertures Récents, métadonnées liste, grille, Home/Drawer/Téléchargements et chronométrage des actions demandées. Les traces debug doivent être capturées si une page PDF reste noire.

## Status

GO RECETTE 6.2
