import 'package:flutter/foundation.dart';

/// A file the user attached and uploaded — a title deed, an ID photo, a
/// licence, a video.
///
/// [storagePath] is where it lives in Supabase Storage (`<uid>/…`). Private
/// documents (deeds, IDs, licences) only ever have a path; public media
/// (videos) also have a [remoteUrl].
@immutable
class UploadedDoc {
  final String name;

  /// Size in bytes. Zero when unknown.
  final int bytes;

  /// Path inside its Storage bucket.
  final String? storagePath;

  /// Public URL, for public media only.
  final String? remoteUrl;

  const UploadedDoc({
    required this.name,
    this.bytes = 0,
    this.storagePath,
    this.remoteUrl,
  });

  /// "1.2 MB". Empty when the size is unknown.
  String get sizeLabel {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// "Uploaded · 1.2 MB".
  String get statusLine =>
      sizeLabel.isEmpty ? 'Uploaded' : 'Uploaded · $sizeLabel';

  /// Shape the database stores: {name, bytes, path}.
  Map<String, dynamic> toJson() => {
        'name': name,
        'bytes': bytes,
        if (storagePath != null) 'path': storagePath,
        if (remoteUrl != null) 'url': remoteUrl,
      };

  factory UploadedDoc.fromJson(Map<String, dynamic> json) => UploadedDoc(
        name: json['name'] as String? ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        storagePath: json['path'] as String?,
        remoteUrl: json['url'] as String?,
      );
}
