class WatchlistPositionPriority {
  const WatchlistPositionPriority._();

  static List<T> apply<T>(
    List<T> items, {
    required bool Function(T item) hasPosition,
    required bool Function(T item) isPinned,
  }) {
    final indexed = items.indexed.toList();
    indexed.sort((a, b) {
      final priorityA = _priority(
        hasPosition: hasPosition(a.$2),
        isPinned: isPinned(a.$2),
      );
      final priorityB = _priority(
        hasPosition: hasPosition(b.$2),
        isPinned: isPinned(b.$2),
      );
      final priorityCompare = priorityA.compareTo(priorityB);
      if (priorityCompare != 0) return priorityCompare;
      return a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList();
  }

  static int _priority({required bool hasPosition, required bool isPinned}) {
    if (hasPosition) return 0;
    if (isPinned) return 1;
    return 2;
  }
}
