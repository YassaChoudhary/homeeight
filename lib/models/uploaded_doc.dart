import 'package:flutter/foundation.dart';

/// A file the user attached — a trade licence, a broker card, a title deed.
///
/// ## Why this is its own type
///
/// Three different screens attach documents (company verification, the listing
/// permit step, and later the agent licence renewal), and all three need the
/// same three facts: what it's called, how big it is, and where it ended up.
/// One type means the "Uploaded · 1.2 MB" row is written once.
///
/// ## No file picker yet
///
/// `image_picker` / `file_picker` are not in `pubspec.yaml`, and adding them
/// means Android manifest and iOS Info.plist changes that can't be verified
/// from here. So the upload affordances build one of these from
/// [UploadedDoc.simulated] instead, which keeps the whole flow walkable on a
/// real phone today.
///
/// When the picker lands, the only change is the call site: build this from the
/// picked file and set [localPath]. [remoteUrl] stays null until Supabase
/// Storage is wired, at which point upload fills it in.
@immutable
class UploadedDoc {
  final String name;

  /// Size in bytes. Zero when unknown.
  final int bytes;

  /// Path on the device, once a real picker returns one.
  final String? localPath;

  /// Storage URL, once the file has been uploaded.
  final String? remoteUrl;

  const UploadedDoc({
    required this.name,
    this.bytes = 0,
    this.localPath,
    this.remoteUrl,
  });

  /// Stand-in used until a file picker exists. Named so nobody mistakes one of
  /// these for a real attachment while reading the code.
  factory UploadedDoc.simulated(String name, {int bytes = 1258291}) =>
      UploadedDoc(name: name, bytes: bytes);

  /// "1.2 MB". Falls back to an empty string when the size is unknown, so the
  /// row reads "Uploaded" rather than "Uploaded · 0 B".
  String get sizeLabel {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// "Uploaded · 1.2 MB" — the green subtitle under the file name.
  String get statusLine =>
      sizeLabel.isEmpty ? 'Uploaded' : 'Uploaded · $sizeLabel';

  Map<String, dynamic> toJson() => {
        'name': name,
        'bytes': bytes,
        if (remoteUrl != null) 'url': remoteUrl,
      };

  factory UploadedDoc.fromJson(Map<String, dynamic> json) => UploadedDoc(
        name: json['name'] as String? ?? '',
        bytes: json['bytes'] as int? ?? 0,
        remoteUrl: json['url'] as String?,
      );
}
