abstract class AppFailure implements Exception {
  const AppFailure(this.message, [this.cause]);
  final String message;
  final Object? cause;
  String get userMessage => message;
  @override
  String toString() => '$runtimeType: $message';
}

class StorageFailure extends AppFailure {
  const StorageFailure(super.message, [super.cause]);
}

class PermissionFailure extends AppFailure {
  const PermissionFailure([
    super.message = 'Autorisation de stockage refusée',
    super.cause,
  ]);
}

class UnsupportedFormatFailure extends AppFailure {
  const UnsupportedFormatFailure([
    super.message = 'Format non pris en charge',
    super.cause,
  ]);
}

class ReaderFailure extends AppFailure {
  const ReaderFailure(super.message, [super.cause]);
}

class ArchiveFailure extends AppFailure {
  const ArchiveFailure(super.message, [super.cause]);
}

/// The archive is encrypted and no password was given.
class PasswordRequiredFailure extends ArchiveFailure {
  const PasswordRequiredFailure([
    super.message = 'Cette archive est protégée par un mot de passe',
  ]);
}

/// The given password does not decrypt the archive.
class WrongPasswordFailure extends ArchiveFailure {
  const WrongPasswordFailure([super.message = 'Mot de passe incorrect']);
}

class CorruptedFileFailure extends AppFailure {
  const CorruptedFileFailure([
    super.message = 'Le fichier est endommagé',
    super.cause,
  ]);
}

class InsufficientSpaceFailure extends AppFailure {
  const InsufficientSpaceFailure([
    super.message = 'Espace de stockage insuffisant',
    super.cause,
  ]);
}

AppFailure mapFailure(Object error) => error is AppFailure
    ? error
    : StorageFailure('Une erreur inattendue est survenue', error);
