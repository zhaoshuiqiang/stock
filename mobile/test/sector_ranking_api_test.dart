import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';

void main() {
  group('Sector ranking API request', () {
    test('builds industry gainer request with page and limit', () {
      final uri = ApiClient.buildSectorRankingUri(
        category: SectorCategory.industry,
        page: 2,
        limit: 120,
        descending: true,
      );

      expect(uri.queryParameters['fs'], 'm:90+t:2');
      expect(uri.queryParameters['pn'], '2');
      expect(uri.queryParameters['pz'], '120');
      expect(uri.queryParameters['fid'], 'f3');
      expect(uri.queryParameters['po'], '1');
    });

    test('builds concept loser request with ascending change percent', () {
      final uri = ApiClient.buildSectorRankingUri(
        category: SectorCategory.concept,
        page: 1,
        limit: 80,
        descending: false,
      );

      expect(uri.queryParameters['fs'], 'm:90+t:3');
      expect(uri.queryParameters['pn'], '1');
      expect(uri.queryParameters['pz'], '80');
      expect(uri.queryParameters['fid'], 'f3');
      expect(uri.queryParameters['po'], '0');
    });
  });
}
