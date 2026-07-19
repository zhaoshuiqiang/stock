import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/analysis/directional_weight_optimizer.dart';

void main() {
  // Ensure global override never leaks between tests.
  tearDown(() => DirectionalEvidenceBuilder.applyWeightOverride(null));

  Map<String, double> defaults() =>
      Map<String, double>.from(DirectionalEvidenceBuilder.componentWeights);

  double sum(Map<String, double> w) => w.values.fold(0.0, (a, b) => a + b);

  group('DirectionalWeightOptimizer.optimize guardrails', () {
    test('too few samples returns normalized defaults', () {
      final result = DirectionalWeightOptimizer.optimize(
        const [],
        defaults: defaults(),
      );
      expect(sum(result), closeTo(1.0, 1e-9));
      for (final k in defaults().keys) {
        expect(result[k], closeTo(defaults()[k]!, 1e-9));
      }
    });

    test('enough samples but too few distinct dates returns defaults', () {
      // 150 samples all on the SAME date -> distinctDates guard trips.
      final date = DateTime(2026, 1, 5);
      final samples = List.generate(
        150,
        (i) => DirectionOutcomeSample(
          components: {'trend': i.isEven ? 0.8 : -0.8},
          realizedReturn: i.isEven ? 2.0 : -2.0,
          signalDate: date,
        ),
      );
      final result = DirectionalWeightOptimizer.optimize(
        samples,
        defaults: defaults(),
        asOf: DateTime(2026, 2, 1),
      );
      expect(result['trend'], closeTo(defaults()['trend']!, 1e-9));
    });
  });

  group('DirectionalWeightOptimizer.optimize learning', () {
    test('agreeing component out-weights disagreeing component', () {
      final base = DateTime(2026, 1, 1);
      final samples = <DirectionOutcomeSample>[];
      for (var i = 0; i < 160; i++) {
        final up = i.isEven;
        final ret = up ? 2.5 : -3.0;
        samples.add(DirectionOutcomeSample(
          // trend always points the right way; reversal always the wrong way.
          components: {
            'trend': up ? 0.8 : -0.8,
            'reversal_momentum': up ? -0.8 : 0.8,
            'volume_flow': 0.5, // constant -> ~chance -> ~unchanged
          },
          realizedReturn: ret,
          signalDate: base.add(Duration(days: i % 30)),
        ));
      }
      final result = DirectionalWeightOptimizer.optimize(
        samples,
        defaults: defaults(),
        asOf: DateTime(2026, 3, 1),
      );
      expect(sum(result), closeTo(1.0, 1e-9));
      // trend and reversal share the same 0.25 default; learning must separate them.
      expect(result['trend']! > result['reversal_momentum']!, isTrue);
      // every weight stays within clamp bounds
      for (final w in result.values) {
        expect(w, greaterThanOrEqualTo(0.0));
        expect(w, lessThanOrEqualTo(0.5));
      }
    });
  });

  group('DirectionalWeightOptimizer.buildSamplesFromRows', () {
    test('parses valid rows and skips malformed', () {
      final rows = <Map<String, dynamic>>[
        {
          'direction_components_json': '{"trend":0.5,"volume_flow":-0.3}',
          'signal_trade_date': '2026-01-05',
          'executable_return': 1.5,
        },
        {
          // missing executable_return -> skipped
          'direction_components_json': '{"trend":0.1}',
          'signal_trade_date': '2026-01-06',
        },
        {
          // bad json -> skipped
          'direction_components_json': 'not-json',
          'signal_trade_date': '2026-01-07',
          'executable_return': 2.0,
        },
      ];
      final samples = DirectionalWeightOptimizer.buildSamplesFromRows(rows);
      expect(samples.length, 1);
      expect(samples.first.components['trend'], 0.5);
      expect(samples.first.realizedReturn, 1.5);
      expect(samples.first.signalDate, DateTime(2026, 1, 5));
    });
  });

  group('DirectionalEvidenceBuilder weight override', () {
    test('effectiveWeights defaults to componentWeights when no override', () {
      DirectionalEvidenceBuilder.applyWeightOverride(null);
      expect(DirectionalEvidenceBuilder.effectiveWeights,
          DirectionalEvidenceBuilder.componentWeights);
    });

    test('override is applied and can be cleared', () {
      final custom = {
        'trend': 0.3,
        'reversal_momentum': 0.2,
        'volume_flow': 0.2,
        'relative_strength': 0.15,
        'next_session': 0.05,
        'sector_momentum': 0.10,
      };
      DirectionalEvidenceBuilder.applyWeightOverride(custom);
      expect(DirectionalEvidenceBuilder.effectiveWeights['trend'], 0.3);
      DirectionalEvidenceBuilder.applyWeightOverride(null);
      expect(DirectionalEvidenceBuilder.effectiveWeights,
          DirectionalEvidenceBuilder.componentWeights);
    });
  });
}
