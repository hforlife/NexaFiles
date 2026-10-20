# NexaFiles

Gestionnaire de fichiers Android et bibliothèque de lecture, hors ligne.
L'objectif : la simplicité d'un « File Manager + » et une lecture agréable de
tous les formats courants, en particulier les mangas et BD.

## Fonctionnalités

**Gestionnaire de fichiers**
- Accès direct à tout le stockage (permission « accès à tous les fichiers ») :
  stockage interne et cartes SD, avec l'espace occupé et libre.
- Accueil par catégories (Images, Vidéos, Audio, Documents, Livres & BD,
  Archives, Applications), issues de l'index média d'Android.
- Accès rapides (Téléchargements, Documents, Appareil photo…) et dossiers favoris.
- Copier, déplacer (instantané sur un même volume), renommer, partager,
  ouvrir avec une autre app, corbeille restaurable (fichiers et dossiers).
- Recherche dans le dossier, tri naturel (`page2` avant `page10`), vue liste
  ou grille, miniatures.
- Navigateur d'archives ZIP, RAR et 7z avec extraction.

**Lecture**

| Format | Lecteur |
|---|---|
| CBZ, CBR, CB7 | Manga/BD : zones de tap, sens de lecture droite → gauche, double page, zoom au double tap, pages préchargées |
| PDF | pdfrx (PDFium) : défilement continu, zoom net, recherche avec surlignage, sélection de texte |
| EPUB | Moteur paginé maison : pages, chapitres enchaînés, position mémorisée, thèmes, polices, recherche |
| DOCX | Conversion HTML intégrée : titres, listes, tableaux, images |
| TXT, Markdown | Lecteur texte |
| Images | Galerie du dossier avec zoom |
| Audio, vidéo | video_player (ExoPlayer), lecture enchaînée du dossier |

XLSX, PPTX, les anciens `.doc` et les APK s'ouvrent dans une app externe.

**Bibliothèque**
- Analyse des dossiers choisis : livres, mangas, PDF, textes, avec leurs couvertures.
- Progression de lecture, « Continuer la lecture », favoris, collections et signets.

## Prérequis

| Outil | Version |
|---|---|
| Flutter | **3.38.10** (Dart 3.10.9) |
| JDK | 17 |
| Android SDK | compileSdk de Flutter (36), minSdk 24 (Android 7.0) |
| Android NDK | **28.2.13676358** (installation obligatoire pour Flutter ≥ 3.29) |
| CMake | 3.22+ (téléchargé par Gradle, utilisé par pdfrx/PDFium) |

Flutter 3.38.10 est la version la plus récente qui fonctionne sur
**macOS 13** : à partir de la 3.41, Flutter exige macOS 14. Sur un Mac à jour,
une version plus récente de Flutter peut être utilisée.

Chaîne Android : Gradle 8.14, AGP 8.11.1, Kotlin 2.2.20.

## Démarrage

```bash
flutter pub get
flutter analyze          # doit afficher « No issues found! »
flutter test             # tests unitaires et widgets
flutter run              # sur un appareil Android branché
flutter build apk --debug
```

Au premier lancement, l'écran Fichiers demande l'accès à tous les fichiers.
Accordez-le dans les réglages Android : l'app revérifie au retour.

> **Play Store** : la permission `MANAGE_EXTERNAL_STORAGE` exige un formulaire
> de justification (accepté pour les gestionnaires de fichiers).
> `applicationId` (`com.example.nexa_file`) et la signature release restent à
> définir avant toute publication.

## Architecture

```
lib/
  app/        démarrage, routes, onglets, thème et tokens de design
  core/       logique sans écran
    archives/   ZIP (accès aléatoire, dart) et RAR/7z (pont Android)
    comics/     source de pages de BD (cache LRU, tri naturel)
    database/   SQLite via drift (bibliothèque, progression, signets…)
    formats/    détection de format par signature et structure
    library/    analyse des dossiers de bibliothèque
    readers/    adaptateurs de lecture (PDF, EPUB, DOCX, texte, image, média)
    storage/    stockage local dart:io, volumes, catégories, types MIME
    trash/      corbeille
  features/   écrans : files, library, recents, reader, archives, settings, tools
  shared/     widgets et formatage communs
android/app/src/main/kotlin/…/
  StorageBridge.kt     permission, volumes, catégories MediaStore, miniatures, partage
  ArchiveBridge.kt     sessions RAR/7z (archive ouverte une fois par lecture)
  EpubWebViewFactory.kt WebView isolée : EPUB paginé et DOCX
```

Principes :
- **Un seul point d'ouverture** des fichiers : `features/reader/file_opener.dart`
  (détection du format, puis lecteur, navigateur d'archives ou app externe).
- Les **E/S de fichiers** se font en Dart (`dart:io`, hors du fil d'interface).
  Le natif ne sert qu'à ce qui exige des API Android.
- La **WebView de lecture** n'a aucun accès réseau, ne lit que le dossier du
  document et retire les scripts du contenu.

## Tests

`test/` couvre la détection de format, la sécurité des archives, le stockage
local (sur un vrai dossier temporaire), les transferts, la corbeille, la
navigation, les lecteurs (BD, DOCX, EPUB), la migration de la base et l'accueil.
Les fichiers `lotN_*_test.dart` suivent les lots de développement.

## État du projet

- Les lots 1 à 8 sont terminés côté code : analyse propre et 101 tests verts.
- **À faire** : premier build Android avec le NDK, puis vérification sur un
  appareil des parties natives non couvertes par les tests (pagination EPUB,
  PDF via PDFium, lecteur vidéo, catégories MediaStore, permission).
- Pistes suivantes : mode webtoon pour les mangas, écran toujours allumé
  pendant la lecture, traduction anglaise complète (une grande partie des
  textes est encore en dur, en français).
