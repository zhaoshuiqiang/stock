# 更新日志

## v2.22.0 (2026-06-14)

### 关键修复

- **回测引擎崩溃修复**: 全胜场景下 profitFactor 为 double.infinity 导致 toStringAsFixed() 崩溃，改用 999.99 表示极大值
- **HTTP连接池泄漏修复**: MarketContextProvider 每次请求创建新 http.Client 未关闭，改为静态复用单例
- **单例 dispose() 后不可用修复**: ExploreEngine/OpportunityEngine/SectorPickEngine 的 StreamController 关闭后无法重建，增加 _ensureController() 自动恢复机制

### 一般修复

- **信号检测修正**: "缩量上涨"信号类型从 buy 修正为 sell
- **策略冲突检测修正**: 使用买卖信号计数判断冲突，避免误判
- **行情客户端重构**: WebSocketClient 重命名为 QuotePollingClient，改为批量轮询模式，延迟初始化 HTTP Client
- **信号引擎优化**: 提取辅助函数，增加多空对抗验证反馈
- **K线数据校验**: API 数据增加 DataValidator 校验
- **策略面板重构**: 提取 StrategyPanelConfigured 公共类，消除重复代码
- **搜索防抖**: 搜索页面增加 debounce Timer 并正确 dispose
- **交易日判断修正**: 增加补班日处理逻辑 _isMakeupDay()

### 细节修复

- **情感分析**: 移除重复的否定词"未能"，修正注释"前2个字符"为"前4个字符"
