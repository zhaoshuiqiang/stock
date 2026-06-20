import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 概念标签数据模型
class ConceptTags {
  final List<String> long;  // 长线概念
  final List<String> short; // 短线概念

  ConceptTags({required this.long, required this.short});

  bool get isEmpty => long.isEmpty && short.isEmpty;

  /// 所有概念名称（用于显示）
  List<String> get all => [...long, ...short];

  /// 用于UI显示的摘要字符串，如 "CPO,先进封装"
  String get summary {
    final allTags = all;
    if (allTags.isEmpty) return '';
    return allTags.take(3).join(',');
  }

  /// 获取指定方向的概念列表作为chips/标签
  List<ConceptTagItem> toTagItems() {
    final items = <ConceptTagItem>[];
    for (final tag in long) {
      items.add(ConceptTagItem(tag: tag, type: ConceptTagType.long));
    }
    for (final tag in short) {
      items.add(ConceptTagItem(tag: tag, type: ConceptTagType.short));
    }
    return items;
  }
}

enum ConceptTagType { long, short }

class ConceptTagItem {
  final String tag;
  final ConceptTagType type;

  ConceptTagItem({required this.tag, required this.type});

  String get label => '${type == ConceptTagType.long ? "长" : "短"}·$tag';
}

/// 概念标签提供者
/// 单例模式，应用启动时加载 concept_tags.json
class ConceptTagProvider {
  static ConceptTagProvider? _instance;
  Map<String, Map<String, List<String>>>? _cache;

  ConceptTagProvider._();

  static ConceptTagProvider get instance {
    _instance ??= ConceptTagProvider._();
    return _instance!;
  }

  bool get isLoaded => _cache != null;

  /// 加载概念标签数据
  Future<void> load() async {
    if (_cache != null) return;

    try {
      final jsonStr = await rootBundle.loadString('assets/concept_tags.json');
      final data = json.decode(jsonStr) as Map<String, dynamic>;

      _cache = {};
      for (final entry in data.entries) {
        if (entry.key.startsWith('_')) continue; // skip _meta
        if (entry.value is Map) {
          _cache![entry.key] = {
            'long': List<String>.from((entry.value as Map)['long'] ?? []),
            'short': List<String>.from((entry.value as Map)['short'] ?? []),
          };
        }
      }
    } catch (e) {
      // JSON文件可能不存在或为空（占位文件），不回退
      debugPrint('ConceptTagProvider: load failed: $e');
      _cache = {};
    }
  }

  /// 获取某只股票的概念标签
  ConceptTags getConceptTags(String code) {
    if (_cache == null) return ConceptTags(long: [], short: []);

    final stockConcepts = _cache![code];
    if (stockConcepts == null) return ConceptTags(long: [], short: []);

    return ConceptTags(
      long: stockConcepts['long'] ?? [],
      short: stockConcepts['short'] ?? [],
    );
  }

  /// 批量获取概念标签摘要
  String getConceptSummary(String code) {
    return getConceptTags(code).summary;
  }

  /// 总概念数量
  int get totalStocks => _cache?.length ?? 0;
}
