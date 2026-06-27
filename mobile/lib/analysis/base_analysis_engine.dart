import 'dart:async';

import 'package:flutter/foundation.dart';

/// 分析引擎基类
///
/// 封装后台分析引擎通用的架构逻辑：运行状态管理、进度广播、
/// StreamController 生命周期管理。子类只需关注业务特定的分析逻辑。
abstract class BaseAnalysisEngine<P> {
  bool _isRunning = false;

  /// 是否正在运行分析
  bool get isRunning => _isRunning;

  StreamController<P>? _progressController;

  /// 进度广播流，切换 Tab 后重新订阅可获取最新进度
  Stream<P> get progressStream => _ensureController().stream;

  P? _latestProgress;

  /// 最新进度快照，切换 Tab 回来后恢复状态
  P? get latestProgress => _latestProgress;

  /// 释放资源并重置内部状态，允许单例后续继续使用
  /// 注意: 不会中止正在运行的分析调用（使用 [_ensureController] 自动重建）
  void dispose() {
    _isRunning = false;
    _progressController?.close();
  }

  /// 获取或重建 StreamController（dispose 后自动重建）
  StreamController<P> _ensureController() {
    if (_progressController == null || _progressController!.isClosed) {
      _progressController = StreamController<P>.broadcast();
    }
    return _progressController!;
  }

  /// 发射进度事件并更新最新快照
  @protected
  void emit(P progress) {
    _latestProgress = progress;
    _ensureController().add(progress);
  }

  /// 尝试启动分析。
  ///
  /// 若已在运行则发射 [alreadyRunningProgress] 并返回 false；
  /// 否则置运行状态为 true 并返回 true。
  @protected
  bool tryStart(P alreadyRunningProgress) {
    if (_isRunning) {
      emit(alreadyRunningProgress);
      return false;
    }
    _isRunning = true;
    return true;
  }

  /// 标记分析结束（应在 finally 块中调用）。
  @protected
  void markFinished() {
    _isRunning = false;
  }
}
