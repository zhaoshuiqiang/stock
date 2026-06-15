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

### Bug修复
- 回测引擎ATR止损失效：4个回测策略(KDJ/RSI/BOLL/MA)补充calcATR调用，ATR止损机制恢复正常
- 止损价可能高于入场价：取最小值逻辑修复，确保止损价始终低于入场价
- 共振评分双重计数：背离信号从DIVER_1+DIVER_2改为单一DIVER，消除虚高0.8分
- 实时行情评分梯度：2-5%涨幅从+2.0调整为+1.5，与5-8%的+2.0形成合理梯度
- confluenceScore语义修正：从bullCount(指标计数)改为score.round(共振评分)，UI同步更新为"共振X/10"
- ADX计算修正：预热期使用初始平均值(避免双重计数)，data.length<2*period时正确除以实际累加数量
- 机会引擎信号遗漏：改用SignalLayer.detectAllSignals，补全量价背离/布林收口等特有信号
- "缩量反弹"标签矛盾：修正为"放量反弹"并增加价格方向校验(close>prev.close)
- 回测尾仓maxDrawdown未更新：6个回测方法尾仓平仓时补充peakEquity/maxDrawdown更新
- KDJ超买区置信度逻辑：区分买入/卖出信号方向，超买区金叉降置信度、超卖区死叉降置信度
- WR=0被错误过滤：移除>0条件，WR=0(收盘价=周期最高价)为有效值
- 置信度信号一致性方向对齐：信号主方向与推荐方向一致时加分，中性评分(5-6分)增加对齐逻辑
- 布林带突破信号方向矛盾：ADX>25趋势行情中突破上轨为买入信号，震荡行情中为卖出信号
- "主力吸筹迹象"信号条件互斥：volDeclining检查范围从近5天改为第-4到-7天，消除条件矛盾
- 进度条颜色阈值不一致：共振评分进度条增加3级颜色(>=6红/>=4橙/绿)，与文本标签一致
- archive_screen共振显示：从"共振X/8"修正为"共振X/10"
