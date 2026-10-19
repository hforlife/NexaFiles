import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.locale);
  final Locale locale;
  bool get _fr => locale.languageCode == 'fr';
  static AppStrings of(BuildContext context) =>
      AppStrings(Localizations.localeOf(context));
  String get appName => 'NexaFiles';
  String get files => _fr ? 'Fichiers' : 'Files';
  String get library => _fr ? 'Bibliothèque' : 'Library';
  String get recents => _fr ? 'Récents' : 'Recents';
  String get tools => _fr ? 'Outils' : 'Tools';
  String get settings => _fr ? 'Paramètres' : 'Settings';
  String get addLocation => _fr ? 'Ajouter un emplacement' : 'Add a location';
  String get noLocations =>
      _fr ? 'Aucun dossier autorisé' : 'No allowed folders';
  String get noLocationsHint => _fr
      ? 'Ajoutez un dossier pour parcourir vos documents sans donner accès à tout le stockage.'
      : 'Add a folder to browse documents without granting access to all storage.';
  String get emptyLibrary =>
      _fr ? 'Votre bibliothèque est vide' : 'Your library is empty';
  String get emptyRecents =>
      _fr ? 'Aucun fichier ouvert récemment' : 'No recently opened files';
  String get appearance => _fr ? 'Apparence' : 'Appearance';
  String get reading => _fr ? 'Lecture' : 'Reading';
  String get storage => _fr ? 'Stockage' : 'Storage';
  String get about => _fr ? 'À propos' : 'About';
  String get system => _fr ? 'Système' : 'System';
  String get light => _fr ? 'Clair' : 'Light';
  String get dark => _fr ? 'Sombre' : 'Dark';
  String get cache => _fr ? 'Gestion du cache' : 'Cache management';
  String get unavailable =>
      _fr ? 'Disponible dans un prochain lot' : 'Available in a future lot';
  String get continueReading =>
      _fr ? 'Continuer la lecture' : 'Continue reading';
  String get documents => 'Documents';
  String get comics => _fr ? 'Mangas / BD' : 'Comics';
  String get books => _fr ? 'Livres' : 'Books';
  String get extractArchive => _fr ? 'Extraire une archive' : 'Extract archive';
  String get createArchive => _fr ? 'Créer une archive' : 'Create archive';
  String get fileInfo => _fr ? 'Informations fichier' : 'File information';
}
