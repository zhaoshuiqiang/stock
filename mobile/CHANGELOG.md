# 更新日志

## v2.23.0 (2026-06-15)

### 新功能
- 自选股置顶：长按股票卡片弹出菜单，支持置顶/取消置顶，置顶股票带📌标识排在最前
- 预警触发机制：实现价格/涨跌幅预警的自动检测与通知推送（5分钟冷却防重复触发）
- 预警通知通道：独立的预警通知渠道，与资讯推送分离

### 优化
- 编辑模式全选：全选范围限定为当前筛选条件下的股票（如筛选"买入"时全选只选中买入的股票）
- 回测展示修复：胜率0%、盈亏比999.99/N/A等异常显示问题已修复，全胜时显示"全胜"
- 移除建议中的免责声明文案

### 重构
- signal_engine.dart 上帝函数拆分：从1054行拆分为9个独立模块（SignalLayer、TechnicalScorer、RealtimeScorer、ConfluenceScorer、ComprehensiveScorer、RiskAnalyzer、OpportunityIdentifier、SuggestionGenerator、ConfidenceCalculator），主函数缩减至287行
- SignalValidator 双重调用消除：ConfidenceCalculator 内部验证结果直接复用
- ConfluenceScorer import 风格统一
