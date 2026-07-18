import '../models/stock_models.dart';
import 'next_session_predictor.dart';

class NextDayPredictionResult {
  final double upProbability;
  final double downProbability;
  final double neutralProbability;
  final int sampleCount;
  final String description;
  final Map<String, String> featureBins;

  NextDayPredictionResult({
    required this.upProbability,
    required this.downProbability,
    required this.neutralProbability,
    required this.sampleCount,
    required this.description,
    required this.featureBins,
  });

  Map<String, dynamic> toJson() {
    return {
      'up_probability': upProbability,
      'down_probability': downProbability,
      'neutral_probability': neutralProbability,
      'sample_count': sampleCount,
      'description': description,
      'feature_bins': featureBins,
    };
  }
}

class NextDayPredictor {
  static const int minSampleSize = 15;

  static const Map<String, double> _featureWeights = {
    'adx': 1.5,
    'macd_cross': 1.5,
    'macd_hist': 1.2,
    'kdj': 1.2,
    'rsi': 1.0,
    'volume': 0.8,
    'ma5_ma10': 0.8,
  };

  static NextDayPredictionResult predict(
      List<HistoryKline> data, QuoteData? quote) {
    final sessionPrediction = NextSessionPredictor.predict(data);
    final currentFeatures =
        data.isNotEmpty ? _extractFeatures(data.last) : <String, String>{};

    return NextDayPredictionResult(
      upProbability: sessionPrediction.nextCloseUpProbability,
      downProbability: sessionPrediction.downsideRiskProbability,
      neutralProbability: sessionPrediction.neutralProbability,
      sampleCount: sessionPrediction.sampleCount,
      description:
          '基于K近邻合并预测，${sessionPrediction.sampleCount}个相似样本',
      featureBins: currentFeatures,
    );
  }

  static Map<String, String> extractFeatureBinsPublic(HistoryKline kline) =>
      _extractFeatures(kline);

  static Map<String, String> _extractFeatures(HistoryKline kline) {
    final features = <String, String>{};

    if (kline.rsi6.isFinite && kline.rsi6 >= 0 && kline.rsi6 <= 100) {
      if (kline.rsi6 >= 70) {
        features['rsi'] = '超买';
      } else if (kline.rsi6 >= 50) {
        features['rsi'] = '偏强';
      } else if (kline.rsi6 >= 30) {
        features['rsi'] = '偏弱';
      } else {
        features['rsi'] = '超卖';
      }
    }

    if (kline.macdHist.isFinite) {
      if (kline.macdHist > 0.001) {
        features['macd_hist'] = '红柱';
      } else if (kline.macdHist < -0.001) {
        features['macd_hist'] = '绿柱';
      } else {
        features['macd_hist'] = '零轴';
      }
    }

    if (kline.macdDif.isFinite && kline.macdDea.isFinite) {
      if (kline.macdDif > kline.macdDea) {
        features['macd_cross'] = '金叉区域';
      } else {
        features['macd_cross'] = '死叉区域';
      }
    }

    if (kline.k.isFinite && kline.k >= 0 && kline.k <= 100) {
      if (kline.k >= 80) {
        features['kdj'] = '超买';
      } else if (kline.k >= 50) {
        features['kdj'] = '偏多';
      } else if (kline.k >= 20) {
        features['kdj'] = '偏空';
      } else {
        features['kdj'] = '超卖';
      }
    }

    if (kline.volMa5 > 0 && kline.volume > 0) {
      final volRatio = kline.volume / kline.volMa5;
      if (volRatio >= 1.5) {
        features['volume'] = '放量';
      } else if (volRatio >= 1.0) {
        features['volume'] = '正常';
      } else {
        features['volume'] = '缩量';
      }
    }

    if (kline.ma5 > 0 && kline.ma10 > 0) {
      features['ma5_ma10'] = kline.ma5 > kline.ma10 ? 'MA5上穿' : 'MA5下穿';
    }

    if (kline.adx14.isFinite && kline.adx14 >= 0 && kline.adx14 <= 100) {
      if (kline.adx14 >= 25) {
        features['adx'] = '趋势明确';
      } else if (kline.adx14 >= 20) {
        features['adx'] = '趋势形成';
      } else {
        features['adx'] = '盘整';
      }
    }

    return features;
  }
}
