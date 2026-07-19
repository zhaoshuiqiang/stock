import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/analysis/fundamental_analyzer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('QuoteData ROE plumbing', () {
    test('roe defaults to null', () {
      final q = QuoteData(code: 'sh600519', price: 1700);
      expect(q.roe, isNull);
    });

    test('copyWith sets and preserves roe', () {
      final q = QuoteData(code: 'sh600519', price: 1700);
      final withRoe = q.copyWith(roe: 18.5);
      expect(withRoe.roe, 18.5);
      // copyWith without roe preserves existing value
      final preserved = withRoe.copyWith(price: 1800);
      expect(preserved.roe, 18.5);
    });

    test('toJson/fromJson round-trips roe', () {
      final q = QuoteData(code: 'sh600519', price: 1700).copyWith(roe: 22.3);
      final restored = QuoteData.fromJson(q.toJson());
      expect(restored.roe, 22.3);
    });

    test('fromJson treats missing roe as null (backward compatible)', () {
      final restored = QuoteData.fromJson({'code': 'sz000001', 'price': 12.0});
      expect(restored.roe, isNull);
    });
  });

  group('FundamentalAnalyzer ROE wiring', () {
    QuoteData sample() => QuoteData(
          code: 'sh600519',
          name: 'Test',
          price: 100,
          pe: 20,
          pb: 3,
          turnover: 3,
          mainNetFlowRate: 2,
        );

    test('null roe keeps legacy (no-ROE) behavior stable', () {
      final a = FundamentalAnalyzer.analyze(sample());
      final b = FundamentalAnalyzer.analyze(sample(), roe: null);
      expect(a.totalScore, b.totalScore);
      // No ROE factor string when roe is absent
      expect(a.factors.any((f) => f.contains('ROE')), isFalse);
    });

    test('high roe changes total score and adds an ROE factor', () {
      final noRoe = FundamentalAnalyzer.analyze(sample());
      final highRoe = FundamentalAnalyzer.analyze(sample(), roe: 25);
      expect(highRoe.totalScore, isNot(equals(noRoe.totalScore)));
      expect(highRoe.factors.any((f) => f.contains('ROE')), isTrue);
    });

    test('negative roe scores lower than excellent roe', () {
      final loss = FundamentalAnalyzer.analyze(sample(), roe: -5);
      final great = FundamentalAnalyzer.analyze(sample(), roe: 25);
      expect(great.totalScore, greaterThan(loss.totalScore));
    });
  });

  group('ApiClient.parseRoeFromDatacenterJson', () {
    test('parses preferred ROEJQ column', () {
      final decoded = {
        'result': {
          'data': [
            {'SECUCODE': '600519.SH', 'ROEJQ': 12.34, 'REPORT_DATE': '2024-09-30'}
          ]
        },
        'success': true,
      };
      expect(ApiClient.parseRoeFromDatacenterJson(decoded), 12.34);
    });

    test('falls back to any key containing ROE', () {
      final decoded = {
        'result': {
          'data': [
            {'SOME_ROE_METRIC': 8.8}
          ]
        }
      };
      expect(ApiClient.parseRoeFromDatacenterJson(decoded), 8.8);
    });

    test('parses numeric string ROE', () {
      final decoded = {
        'result': {
          'data': [
            {'ROE': '15.5'}
          ]
        }
      };
      expect(ApiClient.parseRoeFromDatacenterJson(decoded), 15.5);
    });

    test('returns null for empty data', () {
      expect(
          ApiClient.parseRoeFromDatacenterJson({'result': {'data': []}}), isNull);
    });

    test('returns null for implausible value', () {
      final decoded = {
        'result': {
          'data': [
            {'ROE': 99999}
          ]
        }
      };
      expect(ApiClient.parseRoeFromDatacenterJson(decoded), isNull);
    });

    test('returns null for malformed payloads', () {
      expect(ApiClient.parseRoeFromDatacenterJson(null), isNull);
      expect(ApiClient.parseRoeFromDatacenterJson({}), isNull);
      expect(ApiClient.parseRoeFromDatacenterJson({'result': 'x'}), isNull);
      expect(ApiClient.parseRoeFromDatacenterJson('nope'), isNull);
    });
  });
}
