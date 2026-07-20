#!/usr/bin/env python3
# -*- coding: gbk -*-
"""生成 docs/factor_integration_design.md（UTF-8）。

集成设计为"仅设计、不改 App"的落地方案文档。用 Python 写出以保证 UTF-8
（本机 Write 工具默认 GBK，直接写 .md 会乱码）。可选读取 output/ 下的
composite_weights.csv 使建议权重更具体。
"""

import os

import config


def _load_weights_block() -> str:
    """若已有离线结果，读入 IC 加权权重，拼成表格；否则给占位说明。"""
    path = os.path.join(config.OUTPUT_DIR, 'composite_weights.csv')
    if not os.path.exists(path):
        return '（尚未运行 run_factor_research.py，权重以报告为准）'
    import pandas as pd
    df = pd.read_csv(path)
    lines = ['| 因子 | 建议权重(带符号) |', '| --- | --- |']
    for _, r in df.iterrows():
        lines.append(f"| {r['factor']} | {r['weight']:+.3f} |")
    return '\n'.join(lines)


DOC = '''# 因子评分集成设计（本轮仅设计，不改 App）

> 配套《因子分析与 IC 回测研究报告》(`docs/factor_research_report.md`)。本文件给出
> "若离线验证有效，如何把因子评分接入现有评分系统、输出买卖参考分"的落地设计，
> 本轮不改动任何 App 代码，供确认后再实施。

## 一、研究结论摘要（决定集成取向）

1. 全历史 5 日**合成因子 IC ≈ 0.06（t 显著、IC-IR≈0.28）**，方向由"**低波动 / 低换手 /
   反转**"主导：`amplitude`、`atr_pct`、`turnover`、`vol20` 为强负 IC（t 达 -5 ~ -8），
   `mom5/10/20` 为负 IC（A 股短期呈**反转**而非动量）。
2. **可执行 edge 偏弱**：改用"次日开盘进场"的可执行口径后，短周期分档区分度被侵蚀，
   多空组合在 1 日显著为负、3-5 日近 0；顶档净值仅 10 日口径略转正（年化≈5%、Sharpe≈0.4，
   详见报告第六节）。→ 因子更适合做
   **打分/择时的一个维度与风控约束**，而非独立高频多空策略。
3. **App 评分/推荐的分箱前瞻收益不单调、甚至反向**（“买入/强烈买入”不优于“偏空观望”，
   报告第八节）。→ 现有静态权重的买卖分层信息有限、有改进空间。
4. 关键洞察：实证**支持 App 现有"追高惩罚 / 低波偏好"**（`comprehensive_scorer` 的
   `chaseRiskFactor`/`biasP`），**反对追动量**。因子集成的最大价值是把这些惩罚/偏好
   从"专家拍定"升级为"IC 实证校准"。

## 二、集成目标

- 产出一个 **0-100 的"因子评分"**（截面百分位）作为买卖参考；
- 先"影子运行"（只记录、不影响展示分），验证达标后再灰度并入 `comprehensive_scorer`；
- 复用 App 已算指标（`indicators.dart`），**不新增数据源**。

## 三、因子选择与方向（落地版）

入选门槛：`|均值IC| ≥ 0.015` 且 `|t| ≥ 1.96`（以 5 日为主口径），按 |IC| 取前 8，
权重 ∝ 带符号均值 IC（负 IC 自动反向，即"高波动/高换手/追高 → 减分"）。

当前离线权重（IC 加权，来自 `output/composite_weights.csv`）：

{WEIGHTS}

> 因子命名与 `HistoryKline`/`indicators.dart` 一致，可直接在端上复算，无需新数据。

## 四、IC 计算与权重来源（两条路，可并存）

- **离线定期重算（推荐先用）**：本管线按周/月重算截面 IC → 导出带符号权重 JSON →
  作为 App 端"因子权重配置"（打进 `assets/` 或远端配置）。稳、可审计。
- **端上自学习（进阶）**：把 `directional_weight_optimizer.dart` 从"符号命中率"升级为
  "IC 加权"——用 `decision_outcomes` 累积的已实现收益，按分量做截面/秩 IC，替换现有
  `agreement`（符号命中率）为 `rank-IC`，其余护栏（最小样本/日数/最大调整）保持不变。

## 五、与现有评分整合（两方案，推荐 A）

### 方案 A（推荐，最小侵入）：作为一个新维度并入 `ComprehensiveScorer`

- 在 `comprehensive_scorer.dart` 增加一个 `factorScore`(0-10) 维度，短线口径下给
  8%~12% 权重（从技术/实时维等比例让出），长线口径可略低；
- `factorScore` = 端上按入选因子做**截面标准化后按符号权重合成、再映射到 0-10**；
- 截面标准化需要"同批扫描的一篮子股票"，恰好 `explore_engine`/批量扫描场景具备横截面，
  单只详情页可退化为"用因子的历史分位"近似；
- 与现有三层惩罚（`chaseRiskFactor`×`marketFactor`×`predictionModifier`）**正交叠加**，
  不改惩罚逻辑，仅新增一个经 IC 校准的正向维度。

### 方案 B：重标定方向分量权重（`DirectionalEvidenceBuilder`）

- 复用现成 `DirectionalWeightOptimizer.loadAndApply()` 通道（已支持 override + 版本标签），
  把权重来源换成 IC 加权；
- 适合"短线决策引擎(v3)"这条真实生效链路，但改动面更靠近核心，建议在方案 A 影子验证
  通过后再推进。

### 因子 → App 维度映射（要点）

| 因子族 | App 对应 | 集成动作 |
| --- | --- | --- |
| 波动(atr_pct/vol20/amplitude) | 风险维 / 追高惩罚 | 负向：并入 `factorScore` 且可强化 `biasP`/波动惩罚 |
| 换手/量比(turnover/volratio) | 资金/实时维 | 负向（过热惩罚），校准 `SectorHeatDetector`/实时分 |
| 动量/乖离(mom/bias) | 技术维 | 负向（反转），与"追高惩罚"一致，校准力度 |
| 位置(dist_low20/close_pos) | 技术/结构维 | 超跌反转正向，弱权重 |

## 六、特性开关与灰度（对齐现有 P2.x 框架）

- `ScoringConfig` 新增 `useFactorScore = false`（默认关闭）+ `factorScoreVersion` 版本标签；
- **P1 影子**：扫描时计算 `factorScore` 并写入 `decision_snapshots`（新增列，不影响展示分）；
- **P2 灰度**：`useFactorScore=true`，给小权重（如 8%），A/B 对比 1/3/5 日命中率与 IC；
- **上线门槛**（与 `DecisionCalibrator` 一致）：样本 ≥ 100、信号日 ≥ 20、因子 IC-IR/t 达标、
  且并入后命中率/IC **不低于**现状；否则自动回退默认权重。

## 七、落地步骤

1. 端上实现 `FactorScorer`（静态工具类，复用 `indicators.dart` 输出，纯本地）；
2. 批量扫描接入截面标准化 + 合成 → `factorScore`；影子写库；
3. 离线管线定期导出权重配置；`analyze_decision_accuracy.py` 增加"含/不含因子分"对比；
4. 达标后开 `useFactorScore` 并给小权重，持续监控；
5. 数据库迁移：`decision_snapshots` 增列 `factor_score`（`if (oldVersion < N)` 追加，可空）。

## 八、风险与回退

- **小样本 / regime 漂移**：低波反转在震荡/下跌市有效，单边强势市可能失效 → 保留市场态自适应；
- **执行侵蚀**：可执行 edge 弱 → 因子仅作打分维度与风控，不做独立高频多空；
- **一键回退**：关闭 `useFactorScore` 即恢复既有行为（版本标签保证新旧分数可比、不混淆）。

---
*本设计文档由 scripts/factor_research/gen_integration_design.py 生成；实施前请结合最新离线报告复核。*
'''


def main():
    config.force_utf8_stdout()
    config.ensure_dirs()
    content = DOC.replace('{WEIGHTS}', _load_weights_block())
    out = os.path.join(config.DOCS_DIR, 'factor_integration_design.md')
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write(content)
    print(f'集成设计文档已生成: {out}')


if __name__ == '__main__':
    config.add_self_to_path()
    main()
