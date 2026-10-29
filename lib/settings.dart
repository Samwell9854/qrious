import 'dart:convert';
import 'dart:io';

import 'qr_encoding.dart';
import 'qr_export.dart';
import 'qr_png.dart';

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

  /// Expert mode's pixels per module, as chosen or else from [imageSize].
  int get expertPixelsPerModule => pixelsPerModule ?? imageSize.pixelsPerModule;

  Settings copyWith({
    bool? expertMode,
    ErrorCorrection? errorCorrection,
    ImageSize? imageSize,
    ExportFileType? Function()? saveFileType,
    int? pixelsPerModule,
    int? quietZone,
  }) => Settings(
    expertMode: expertMode ?? this.expertMode,
    errorCorrection: errorCorrection ?? this.errorCorrection,
    imageSize: imageSize ?? this.imageSize,
    saveFileType: saveFileType != null ? saveFileType() : this.saveFileType,
    pixelsPerModule: pixelsPerModule ?? this.pixelsPerModule,
    quietZone: quietZone ?? this.quietZone,
  );

  /// Enum names rather than labels, so renaming a label does not lose anyone's choice.
  Map<String, Object?> toJson() => {
    'expertMode': expertMode,
    'errorCorrection': errorCorrection.name,
    'imageSize': imageSize.name,
    'saveFileType': saveFileType?.name ?? 'ask',
    'pixelsPerModule': ?pixelsPerModule,
    'quietZone': quietZone,
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
      other.quietZone == quietZone;

  @override
  int get hashCode => Object.hash(
    expertMode,
    errorCorrection,
    imageSize,
    saveFileType,
    pixelsPerModule,
    quietZone,
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
