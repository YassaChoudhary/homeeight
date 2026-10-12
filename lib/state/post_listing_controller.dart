import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/async_value.dart';
import '../data/listing_repository.dart';
import '../models/listing_draft.dart';
import '../models/my_listing.dart';
import '../models/property.dart';
import '../models/uploaded_doc.dart';

/// A file picked on the phone, ready to upload.
@immutable
class PickedFile {
  final Uint8List bytes;
  final String name;
  final String? mimeType;

  const PickedFile({required this.bytes, required this.name, this.mimeType});
}

/// The single-file upload slots on the draft.
enum DocSlot { video, titleDeed, idFront, idBack, selfie }

/// Owns one in-progress listing: the draft, the current step, uploads, and the
/// live fair-price band under the price field.
///
/// Screens render off this and change things through its methods; none of
/// them touches the repository.
class PostListingController extends ChangeNotifier {
  final ListingRepository _repository;

  /// Who is posting — sent with submit for the listing's agent card.
  final ListerSummary? lister;

  /// Account not verified yet: drafts only, Publish locked.
  final bool accountPending;

  PostListingController(
    this._repository, {
    ListingDraft initial = const ListingDraft(),
    this.lister,
    this.accountPending = false,
  }) : _draft = initial;

  ListingDraft _draft;
  PostStep _step = PostStep.basics;

  bool _saving = false;
  bool _submitting = false;
  Object? _error;

  /// Slots currently uploading (video, deed, ID sides, selfie).
  final Set<DocSlot> _uploadingSlots = {};

  /// Files uploaded in this session and not yet saved anywhere. Removing one
  /// deletes it from Storage; saved files are left for the listing.
  final Set<String> _sessionPhotoPaths = {};

  AsyncValue<FairPrice>? _guidance;
  Timer? _guidanceDebounce;
  int _guidanceRequestId = 0;
  bool _disposed = false;

  ListingDraft get draft => _draft;
  PostStep get step => _step;
  bool get saving => _saving;
  bool get submitting => _submitting;
  Object? get error => _error;
  AsyncValue<FairPrice>? get guidance => _guidance;

  bool isUploading(DocSlot slot) => _uploadingSlots.contains(slot);
  bool get anyUploading => _uploadingSlots.isNotEmpty || _draft.photosUploading;

  bool get isPersisted => _draft.id != null;

  bool get canAdvance => _draft.completed(_step) && !anyUploading;

  /// Message from the last failure, for snackbars.
  String get errorMessage {
    final e = _error;
    if (e is RepositoryException) return e.message;
    return 'Something went wrong. Try again.';
  }

  // --- Editing -------------------------------------------------------------

  void edit(ListingDraft Function(ListingDraft draft) transform) {
    final next = transform(_draft);
    if (identical(next, _draft)) return;

    final bandStale = next.price != _draft.price ||
        next.bua != _draft.bua ||
        next.areaUnit != _draft.areaUnit ||
        next.beds != _draft.beds ||
        next.period != _draft.period ||
        next.purpose != _draft.purpose ||
        next.segment != _draft.segment ||
        next.countryCode != _draft.countryCode ||
        next.propertyType != _draft.propertyType;

    _draft = next;
    _safeNotify();
    if (bandStale) _refreshGuidance();
  }

  void goTo(PostStep step) {
    if (_step == step) return;
    _step = step;
    _safeNotify();
  }

  /// Next step. False at the end — the host then opens Preview.
  bool next() {
    final order = PostStep.numbered;
    final index = order.indexOf(_step);
    if (index >= order.length - 1) return false;
    goTo(order[index + 1]);
    return true;
  }

  /// Previous step. False at the first — the host then closes.
  bool back() {
    final index = PostStep.numbered.indexOf(_step);
    if (index <= 0) return false;
    goTo(PostStep.numbered[index - 1]);
    return true;
  }

  // --- Photos --------------------------------------------------------------

  static const int maxPhotos = 30;

  /// Adds the picked photos straight away (showing the picked image) and
  /// uploads them one by one in the background.
  Future<void> addPhotos(List<PickedFile> files) async {
    final room = maxPhotos - _draft.photos.length;
    if (room <= 0 || files.isEmpty) return;
    final batch = files.take(room).toList();
    final now = DateTime.now().microsecondsSinceEpoch;

    final added = <DraftPhoto>[
      for (var i = 0; i < batch.length; i++)
        DraftPhoto(
          id: 'ph_${now}_$i',
          seed: _draft.photos.length * 3 + i + 1,
          bytes: batch[i].bytes,
          state: PhotoUploadState.uploading,
        ),
    ];
    edit((d) => d.copyWith(photos: [...d.photos, ...added]));

    for (var i = 0; i < batch.length; i++) {
      await _uploadPhoto(added[i].id, batch[i]);
      if (_disposed) return;
    }
  }

  /// Tap on a failed tile.
  Future<void> retryPhoto(String id) async {
    final photo = _photo(id);
    final bytes = photo?.bytes;
    if (photo == null || bytes == null) return;
    _replacePhoto(id, photo.copyWith(state: PhotoUploadState.uploading));
    await _uploadPhoto(
        id, PickedFile(bytes: bytes, name: 'photo.jpg', mimeType: 'image/jpeg'));
  }

  Future<void> _uploadPhoto(String id, PickedFile file) async {
    try {
      final stored = await _repository.uploadListingFile(
        kind: ListingFileKind.photo,
        bytes: file.bytes,
        fileName: file.name,
        contentType: file.mimeType,
      );
      if (_disposed) return;
      final current = _photo(id);
      if (current == null) {
        // Removed while uploading — tidy up.
        _deleteQuietly(ListingFileKind.photo, stored.storagePath);
        return;
      }
      if (stored.storagePath != null) _sessionPhotoPaths.add(stored.storagePath!);
      final realUrl = stored.remoteUrl?.startsWith('http') ?? false;
      _replacePhoto(
        id,
        current.copyWith(
          remoteUrl: stored.remoteUrl,
          storagePath: stored.storagePath,
          state: PhotoUploadState.done,
          // Network image takes over once there's a real URL.
          dropBytes: realUrl,
        ),
      );
    } catch (e) {
      if (_disposed) return;
      _error = e;
      final current = _photo(id);
      if (current != null) {
        _replacePhoto(id, current.copyWith(state: PhotoUploadState.failed));
      }
    }
  }

  void removePhoto(String id) {
    final photo = _photo(id);
    if (photo == null) return;
    final path = photo.storagePath;
    if (path != null && _sessionPhotoPaths.remove(path)) {
      _deleteQuietly(ListingFileKind.photo, path);
    }
    edit((draft) {
      final next = draft.photos.where((p) => p.id != id).toList();
      final removedIndex = draft.photos.indexWhere((p) => p.id == id);
      var cover = draft.coverIndex;
      if (removedIndex >= 0 && removedIndex <= cover && cover > 0) cover -= 1;
      return draft.copyWith(
        photos: next,
        coverIndex: next.isEmpty ? 0 : cover.clamp(0, next.length - 1),
      );
    });
  }

  void setCover(int index) => edit((d) => d.copyWith(coverIndex: index));

  DraftPhoto? _photo(String id) {
    for (final p in _draft.photos) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _replacePhoto(String id, DraftPhoto photo) {
    edit((d) => d.copyWith(
          photos: [for (final p in d.photos) p.id == id ? photo : p],
        ));
  }

  // --- Single files: video, deed, ID, selfie ---------------------------------

  /// Uploads one file into [slot]. Returns false (with [errorMessage] set)
  /// on failure.
  Future<bool> uploadDoc(DocSlot slot, PickedFile file) async {
    if (_uploadingSlots.contains(slot)) return false;
    _uploadingSlots.add(slot);
    _error = null;
    _safeNotify();
    try {
      final stored = await _repository.uploadListingFile(
        kind: slot == DocSlot.video
            ? ListingFileKind.video
            : ListingFileKind.privateDoc,
        bytes: file.bytes,
        fileName: file.name,
        contentType: file.mimeType,
      );
      if (_disposed) return false;
      final previous = _docIn(slot);
      edit((d) => switch (slot) {
            DocSlot.video => d.copyWith(video: stored),
            DocSlot.titleDeed => d.copyWith(titleDeed: stored),
            DocSlot.idFront => d.copyWith(idFront: stored),
            DocSlot.idBack => d.copyWith(idBack: stored),
            DocSlot.selfie => d.copyWith(selfie: stored),
          });
      // Replacing a file uploaded in this session: drop the old one.
      if (previous?.storagePath != null &&
          _sessionPhotoPaths.remove(previous!.storagePath)) {
        _deleteQuietly(_kindFor(slot), previous.storagePath);
      }
      if (stored.storagePath != null) _sessionPhotoPaths.add(stored.storagePath!);
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _uploadingSlots.remove(slot);
      _safeNotify();
    }
  }

  void removeDoc(DocSlot slot) {
    final doc = _docIn(slot);
    if (doc?.storagePath != null && _sessionPhotoPaths.remove(doc!.storagePath)) {
      _deleteQuietly(_kindFor(slot), doc.storagePath);
    }
    edit((d) => switch (slot) {
          DocSlot.video => d.copyWith(clearVideo: true),
          DocSlot.titleDeed => d.copyWith(clearTitleDeed: true),
          DocSlot.idFront => d.copyWith(clearIdFront: true),
          DocSlot.idBack => d.copyWith(clearIdBack: true),
          DocSlot.selfie => d.copyWith(clearSelfie: true),
        });
  }

  UploadedDoc? _docIn(DocSlot slot) => switch (slot) {
        DocSlot.video => _draft.video,
        DocSlot.titleDeed => _draft.titleDeed,
        DocSlot.idFront => _draft.idFront,
        DocSlot.idBack => _draft.idBack,
        DocSlot.selfie => _draft.selfie,
      };

  static ListingFileKind _kindFor(DocSlot slot) =>
      slot == DocSlot.video ? ListingFileKind.video : ListingFileKind.privateDoc;

  void _deleteQuietly(ListingFileKind kind, String? path) {
    if (path == null) return;
    unawaited(_repository.deleteListingFiles(kind, [path]));
  }

  // --- Price guidance ------------------------------------------------------

  void _refreshGuidance() {
    _guidanceDebounce?.cancel();

    if ((_draft.price ?? 0) <= 0 || (_draft.bua ?? 0) <= 0) {
      _guidance = null;
      _safeNotify();
      return;
    }

    _guidance = const AsyncValue.loading();
    _safeNotify();

    _guidanceDebounce = Timer(const Duration(milliseconds: 400), () async {
      final id = ++_guidanceRequestId;
      try {
        final band = await _repository.priceGuidance(_draft);
        if (_disposed || id != _guidanceRequestId) return;
        _guidance = AsyncValue.data(band);
      } catch (e, s) {
        if (_disposed || id != _guidanceRequestId) return;
        _guidance = AsyncValue.error(e, s);
      }
      _safeNotify();
    });
  }

  void retryGuidance() => _refreshGuidance();

  // --- Persistence ---------------------------------------------------------

  /// "Save". Stores the draft in the database (status Draft).
  Future<bool> saveDraft() async {
    if (_saving) return false;
    _saving = true;
    _error = null;
    _safeNotify();
    try {
      final saved = await _repository.saveListingDraft(_draft);
      _draft = saved;
      // Saved photos belong to the listing now.
      _sessionPhotoPaths.clear();
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _saving = false;
      _safeNotify();
    }
  }

  /// "Publish listing" → In review. Null on failure, with [errorMessage].
  Future<MyListing?> submit() async {
    if (_submitting) return null;
    _submitting = true;
    _error = null;
    _safeNotify();
    try {
      final listing = await _repository.submitListing(_draft, lister: lister);
      _draft = listing.draft;
      _sessionPhotoPaths.clear();
      return listing;
    } catch (e) {
      _error = e;
      return null;
    } finally {
      _submitting = false;
      _safeNotify();
    }
  }

  /// Closing without saving: delete what this session uploaded.
  void discardUploads() {
    for (final p in _draft.photos) {
      final path = p.storagePath;
      if (path != null && _sessionPhotoPaths.remove(path)) {
        _deleteQuietly(ListingFileKind.photo, path);
      }
    }
    for (final slot in DocSlot.values) {
      final path = _docIn(slot)?.storagePath;
      if (path != null && _sessionPhotoPaths.remove(path)) {
        _deleteQuietly(_kindFor(slot), path);
      }
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _guidanceDebounce?.cancel();
    super.dispose();
  }
}
