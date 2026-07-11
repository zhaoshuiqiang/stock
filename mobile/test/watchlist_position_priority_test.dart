import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/watchlist_position_priority.dart';

void main() {
  group('WatchlistPositionPriority', () {
    test('keeps holding stocks above manually pinned and normal stocks', () {
      final items = [
        _Item('normal-a'),
        _Item('pinned', pinned: true),
        _Item('holding-b', holding: true),
        _Item('normal-b'),
        _Item('holding-a', holding: true),
      ];

      final sorted = WatchlistPositionPriority.apply(
        items,
        hasPosition: (item) => item.holding,
        isPinned: (item) => item.pinned,
      );

      expect(
        sorted.map((item) => item.code),
        ['holding-b', 'holding-a', 'pinned', 'normal-a', 'normal-b'],
      );
    });
  });
}

class _Item {
  final String code;
  final bool holding;
  final bool pinned;

  const _Item(this.code, {this.holding = false, this.pinned = false});
}
