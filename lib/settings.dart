import 'dart:convert';
import 'dart:io';

import 'qr_encoding.dart';
import 'qr_export.dart';
import 'qr_png.dart';
import 'qr_segments.dart';

/// What the app starts each launch with. The output controls beside the preview start
/// from these and then change the current code only.
class Settings {
  const Settings({
    this.expertMode = false,
    this.errorCorrection = ErrorCorrection.auto,
    this.imageSize = ImageSize.medium,
    this.saveFileType,
    this.pixelsPerModule,
    this.quietZone = quietZoneModules,
    this.version,
    this.mask,
    this.encodingMode,
  });

  /// Whether the app offers everything the spec allows rather than the beginner set.
  /// Unlike the rest, it is not a default for new codes, and Reset leaves it alone.
  final bool expertMode;

  final ErrorCorrection errorCorrection;
  final ImageSize imageSize;

  /// The type Save writes without asking; null asks each time with a menu.
  final ExportFileType? saveFileType;

  /// Expert mode's image size, in any whole number of pixels per module; null until
  /// one is chosen, which starts it from [imageSize]. Kept apart from [imageSize] so
  /// that each mode keeps its own choice.
  final int? pixelsPerModule;

  /// Expert mode's quiet zone, in modules. Beginner mode always has the spec's 4.
  final int quietZone;

  /// Expert mode's symbol version, 1 to 40; null picks the smallest that fits.
  final int? version;

  /// Expert mode's mask pattern, 0 to 7; null picks the one the spec scores best.
  final int? mask;

  /// Expert mode's one mode for the whole payload; null splits it automatically.
  final EncodingMode? encodingMode;

  /// Expert mode's pixels per module, as chosen or else from [imageSize].
  int get expertPixelsPerModule => pixelsPerModule ?? imageSize.pixelsPerModule;

  Settings copyWith({
    bool? expertMode,
    ErrorCorrection? errorCorrection,
    ImageSize? imageSize,
    ExportFileType? Function()? saveFileType,
    int? pixelsPerModule,
    int? quietZone,
    int? Function()? version,
    int? Function()? mask,
    EncodingMode? Function()? encodingMode,
  }) => Settings(
    expertMode: expertMode ?? this.expertMode,
    errorCorrection: errorCorrection ?? this.errorCorrection,
    imageSize: imageSize ?? this.imageSize,
    saveFileType: saveFileType != null ? saveFileType() : this.saveFileType,
    pixelsPerModule: pixelsPerModule ?? this.pixelsPerModule,
    quietZone: quietZone ?? this.quietZone,
    version: version != null ? version() : this.version,
    mask: mask != null ? mask() : this.mask,
    encodingMode: encodingMode != null ? encodingMode() : this.encodingMode,
  );

  /// Enum names rather than labels, so renaming a label does not lose anyone's choice.
  Map<String, Object?> toJson() => {
    'expertMode': expertMode,
    'errorCorrection': errorCorrection.name,
    'imageSize': imageSize.name,
    'saveFileType': saveFileType?.name ?? 'ask',
    'pixelsPerModule': ?pixelsPerModule,
    'quietZone': quietZone,
    'version': version ?? 'auto',
    'mask': mask ?? 'auto',
    'encodingMode': encodingMode?.name ?? 'auto',
  };

  /// Each value falls back to its default on its own when it is missing or unknown, so
  /// a hand edit gone wrong, or a file from a newer version, costs one setting at most.
  factory Settings.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    T? named<T extends Enum>(List<T> values, Object? name) =>
        values.where((v) => v.name == name).firstOrNull;
    const defaults = Settings();
    return Settings(
      expertMode: switch (map['expertMode']) {
        final bool expert => expert,
        _ => defaults.expertMode,
      },
      errorCorrection:
          named(ErrorCorrection.values, map['errorCorrection']) ??
          defaults.errorCorrection,
      imageSize:
          named(ImageSize.values, map['imageSize']) ?? defaults.imageSize,
      saveFileType: named(ExportFileType.values, map['saveFileType']),
      pixelsPerModule: switch (map['pixelsPerModule']) {
        final int n when n >= 1 => n,
        _ => null,
      },
      quietZone: switch (map['quietZone']) {
        final int n when n >= 0 => n,
        _ => defaults.quietZone,
      },
      version: switch (map['version']) {
        final int n when n >= 1 && n <= 40 => n,
        _ => null,
      },
      mask: switch (map['mask']) {
        final int n when n >= 0 && n <= 7 => n,
        _ => null,
      },
      encodingMode: named(EncodingMode.values, map['encodingMode']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.expertMode == expertMode &&
      other.errorCorrection == errorCorrection &&
      other.imageSize == imageSize &&
      other.saveFileType == saveFileType &&
      other.pixelsPerModule == pixelsPerModule &&
      other.quietZone == quietZone &&
      other.version == version &&
      other.mask == mask &&
      other.encodingMode == encodingMode;

  @override
  int get hashCode => Object.hash(
    expertMode,
    errorCorrection,
    imageSize,
    saveFileType,
    pixelsPerModule,
    quietZone,
    version,
    mask,
    encodingMode,
  );
}

/// Writes [settings] where the next launch reads them. Throws when that fails.
typedef SettingsSaver = Future<void> Function(Settings settings);

/// `$XDG_CONFIG_HOME/qrious/settings.json`, or under `~/.config` when that is unset,
/// as the XDG base directory spec says. Null when neither can be worked out.
File? settingsFile([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  final config = switch ((env['XDG_CONFIG_HOME'], env['HOME'])) {
    // The spec says a relative XDG_CONFIG_HOME is invalid and is to be ignored.
    (final xdg?, _) when xdg.startsWith('/') => xdg,
    (_, final home?) when home.isNotEmpty => '$home/.config',
    _ => null,
  };
  return config == null ? null : File('$config/qrious/settings.json');
}

/// The saved settings, or the defaults when there are none or the file is unreadable:
/// a broken settings file must not stop the app from opening.
Future<Settings> loadSettings([File? file]) async {
  file ??= settingsFile();
  if (file == null) return const Settings();
  try {
    return Settings.fromJson(jsonDecode(await file.readAsString()));
  } on Exception {
    return const Settings();
  }
}

/// Writes [settings] to [file] (the default location when null), creating its folder.
/// Written beside it and renamed over it, so a crash mid-write leaves the old file
/// whole rather than a truncated one.
Future<void> saveSettings(Settings settings, [File? file]) async {
  file ??= settingsFile();
  if (file == null) {
    throw const FileSystemException(
      'No home or config folder to save settings in',
    );
  }
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(settings.toJson())}\n',
  );
  await temporary.rename(file.path);
}
