/// A tiny, dependency-free representation of "something loaded over time".
///
/// Every screen that will eventually read from the backend renders off one of
/// these instead of a raw list, so wiring the real API later is a repository
/// swap rather than a UI rewrite: the loading, empty and error branches already
/// exist and are already laid out.
sealed class AsyncValue<T> {
  const AsyncValue();

  const factory AsyncValue.loading() = AsyncLoading<T>;
  const factory AsyncValue.data(T value) = AsyncData<T>;
  const factory AsyncValue.error(Object error, [StackTrace? stackTrace]) =
      AsyncError<T>;

  T? get valueOrNull => this is AsyncData<T> ? (this as AsyncData<T>).value : null;

  bool get isLoading => this is AsyncLoading<T>;
  bool get hasError => this is AsyncError<T>;

  R when<R>({
    required R Function() loading,
    required R Function(T value) data,
    required R Function(Object error) error,
  }) {
    final self = this;
    return switch (self) {
      AsyncLoading<T>() => loading(),
      AsyncData<T>(value: final v) => data(v),
      AsyncError<T>(error: final e) => error(e),
    };
  }
}

class AsyncLoading<T> extends AsyncValue<T> {
  const AsyncLoading();
}

class AsyncData<T> extends AsyncValue<T> {
  final T value;
  const AsyncData(this.value);
}

class AsyncError<T> extends AsyncValue<T> {
  final Object error;
  final StackTrace? stackTrace;
  const AsyncError(this.error, [this.stackTrace]);
}

/// Thrown by repositories so the UI has one error type to render, whatever the
/// transport underneath ends up being.
class RepositoryException implements Exception {
  final String message;
  final int? statusCode;
  const RepositoryException(this.message, {this.statusCode});

  @override
  String toString() => 'RepositoryException($statusCode): $message';
}
