import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/async_value.dart';
import '../data/listing_repository.dart';
import '../models/listing_draft.dart';
import '../models/my_listing.dart';
import '../models/property.dart';

/// Owns one in-progress listing: the draft, where the user is in the stepper,
/// and the live fair-price band under the price field.
///
/// Same division of labour as `ListingsController`. The screens render off this
/// and mutate through the named methods; none of them touches the repository,
/// so swapping the mock for Supabase changes nothing above this file.
///
/// ## Why one controller for the whole flow
///
/// The steps are not independent — the price band depends on the BUA typed two
/// fields earlier, the preview reads everything, and "Save" from any step has
/// to persist the same object. A controller per screen would mean lifting all
/// of that into the host anyway.
class PostListingController extends ChangeNotifier {
  final ListingRepository _repository;

  PostListingController(
    this._repository, {
    ListingDraft initial = const ListingDraft(),
  }) : _draft = initial;

  ListingDraft _draft;
  PostStep _step = PostStep.basics;

  bool _saving = false;
  bool _submitting = false;
  Object? _error;

  /// The band under the price field. Null before there's enough entered to ask
  /// for one — an empty callout is worse than no callout.
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

  /// True when the draft has been persisted at least once, which is what makes
  /// "Continue editing" on My Listings possible.
  bool get isPersisted => _draft.id != null;

  /// Whether the current step's CTA should be enabled.
  bool get canAdvance => _draft.completed(_step);

  // --- Editing -------------------------------------------------------------

  /// The single mutation point. Every field editor goes through this, so there
  /// is one place that decides what a change invalidates.
  void edit(ListingDraft Function(ListingDraft draft) transform) {
    final next = transform(_draft);
    if (identical(next, _draft)) return;

    // Anything that moves the price band re-asks for it. Checked here rather
    // than at each call site so a new field can't quietly skip the refresh.
    final bandStale = next.price != _draft.price ||
        next.bua != _draft.bua ||
        next.beds != _draft.beds ||
        next.furnishing != _draft.furnishing ||
        next.purpose != _draft.purpose ||
        next.propertyType != _draft.propertyType;

    _draft = next;
    notifyListeners();
    if (bandStale) _refreshGuidance();
  }

  void goTo(PostStep step) {
    if (_step == step) return;
    _step = step;
    notifyListeners();
  }

  /// Advances to the next numbered step. Returns false at the end of the
  /// stepper, which is the host's signal to push the Preview screen.
  bool next() {
    final order = PostStep.numbered;
    final index = order.indexOf(_step);
    // Location isn't in the numbered list; from there, "next" means Details.
    if (index < 0) {
      goTo(PostStep.details);
      return true;
    }
    if (index >= order.length - 1) return false;
    goTo(order[index + 1]);
    return true;
  }

  /// Steps back. Returns false when there's nowhere left to go, which is the
  /// host's signal to close the flow.
  bool back() {
    if (_step == PostStep.location) {
      goTo(PostStep.basics);
      return true;
    }
    final index = PostStep.numbered.indexOf(_step);
    if (index <= 0) return false;
    goTo(PostStep.numbered[index - 1]);
    return true;
  }

  // --- Price guidance ------------------------------------------------------

  /// Debounced at 280ms, matching the search field: one request per pause
  /// rather than one per digit typed into the price box.
  void _refreshGuidance() {
    _guidanceDebounce?.cancel();

    if ((_draft.price ?? 0) <= 0 || (_draft.bua ?? 0) <= 0) {
      _guidance = null;
      _safeNotify();
      return;
    }

    _guidance = const AsyncValue.loading();
    _safeNotify();

    _guidanceDebounce = Timer(const Duration(milliseconds: 280), () async {
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

  /// Retry hook for the error branch of the band callout.
  void retryGuidance() => _refreshGuidance();

  // --- Persistence ---------------------------------------------------------

  /// "Save" in the stepper header. Keeps the user where they are — this is a
  /// safety net, not an exit.
  Future<bool> saveDraft() async {
    if (_saving) return false;
    _saving = true;
    _error = null;
    _safeNotify();
    try {
      _draft = await _repository.saveListingDraft(_draft);
      return true;
    } catch (e) {
      _error = e;
      return false;
    } finally {
      _saving = false;
      _safeNotify();
    }
  }

  /// Publishes. Returns the created listing, or null on failure with [error]
  /// set — the caller shows the failure rather than navigating.
  Future<MyListing?> submit() async {
    if (_submitting) return null;
    _submitting = true;
    _error = null;
    _safeNotify();
    try {
      return await _repository.submitListing(_draft);
    } catch (e) {
      _error = e;
      return null;
    } finally {
      _submitting = false;
      _safeNotify();
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
