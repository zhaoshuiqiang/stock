#!/usr/bin/env python3
"""
评分机制准确性分析脚本
分析留档数据的评分准确性和推荐胜率，生成优化建议报告
"""

import sqlite3
import os
import json
from datetime import datetime, timedelta
from collections import defaultdict
from typing import List, Dict, Tuple
import statistics

# 数据库路径
DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'mobile', 'stock_analysis.db')
REPORT_PATH = os.path.join(os.path.dirname(__file__), '..', 'docs', 'scoring_analysis_report.md')

def get_db_connection():
    """获取数据库连接"""
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(f"数据库文件不存在: {DB_PATH}")
    return sqlite3.connect(DB_PATH)

def fetch_archive_records(conn, days_back=30):
    """获取最近N天的留档记录"""
    cursor = conn.cursor()
    cutoff_date = (datetime.now() - timedelta(days=days_back)).timestamp() * 1000
    
    query = """
    SELECT 
        code,
        name,
        price,
        change_pct,
        score,
        recommendation,
        risk_level,
        buy_signal_count,
        sell_signal_count,
        active_strategy_count,
        confluence_score,
        archived_at
    FROM archive_records
    WHERE archived_at >= ?
    ORDER BY archived_at DESC
    """
    
    cursor.execute(query, (cutoff_date,))
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]

def fetch_recommendation_tracking(conn, days_back=30):
    """获取推荐追踪数据（包含实际收益）"""
    cursor = conn.cursor()
    cutoff_date = (datetime.now() - timedelta(days=days_back)).timestamp() * 1000
    
    query = """
    SELECT 
        code,
        name,
        signal_price,
        signal_date,
        day5_price,
        day5_return,
        day10_price,
        day10_return,
        day20_price,
        day20_return
    FROM recommendation_tracking
    WHERE signal_date >= ?
    ORDER BY signal_date DESC
    """
    
    cursor.execute(query, (cutoff_date,))
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]

def analyze_recommendation_accuracy(archives: List[Dict], tracking: List[Dict]) -> Dict:
    """分析推荐准确性"""
    results = {
        'by_recommendation': defaultdict(lambda: {'total': 0, 'wins': 0, 'avg_return': 0}),
        'by_score_range': defaultdict(lambda: {'total': 0, 'wins': 0, 'avg_return': 0}),
        'by_risk_level': defaultdict(lambda: {'total': 0, 'wins': 0, 'avg_return': 0}),
        'high_score_failures': [],
        'low_score_successes': [],
    }
    
    # 建立代码到追踪数据的映射
    tracking_map = {t['code']: t for t in tracking}
    
    for archive in archives:
        code = archive['code']
        score = archive['score']
        recommendation = archive['recommendation']
        risk_level = archive['risk_level']
        
        # 获取实际收益（优先使用5日收益，其次10日，最后20日）
        if code in tracking_map:
            track = tracking_map[code]
            actual_return = track.get('day5_return') or track.get('day10_return') or track.get('day20_return')
            
            if actual_return is not None:
                # 按推荐类型统计
                rec_key = recommendation
                results['by_recommendation'][rec_key]['total'] += 1
                results['by_recommendation'][rec_key]['avg_return'] += actual_return
                if actual_return > 0:
                    results['by_recommendation'][rec_key]['wins'] += 1
                
                # 按评分区间统计
                score_range = get_score_range(score)
                results['by_score_range'][score_range]['total'] += 1
                results['by_score_range'][score_range]['avg_return'] += actual_return
                if actual_return > 0:
                    results['by_score_range'][score_range]['wins'] += 1
                
                # 按风险等级统计
                results['by_risk_level'][risk_level]['total'] += 1
                results['by_risk_level'][risk_level]['avg_return'] += actual_return
                if actual_return > 0:
                    results['by_risk_level'][risk_level]['wins'] += 1
                
                # 识别高评分但表现差的案例
                if score >= 80 and actual_return < -3:
                    results['high_score_failures'].append({
                        'code': code,
                        'name': archive['name'],
                        'score': score,
                        'recommendation': recommendation,
                        'return': actual_return,
                        'date': datetime.fromtimestamp(archive['archived_at'] / 1000).strftime('%Y-%m-%d')
                    })
                
                # 识别低评分但表现好的案例
                if score < 60 and actual_return > 5:
                    results['low_score_successes'].append({
                        'code': code,
                        'name': archive['name'],
                        'score': score,
                        'recommendation': recommendation,
                        'return': actual_return,
                        'date': datetime.fromtimestamp(archive['archived_at'] / 1000).strftime('%Y-%m-%d')
                    })
    
    # 计算平均收益和胜率
    for category in ['by_recommendation', 'by_score_range', 'by_risk_level']:
        for key in results[category]:
            data = results[category][key]
            if data['total'] > 0:
                data['avg_return'] = data['avg_return'] / data['total']
                data['win_rate'] = (data['wins'] / data['total']) * 100
            else:
                data['avg_return'] = 0
                data['win_rate'] = 0
    
    return results

def get_score_range(score: int) -> str:
    """将评分转换为区间"""
    if score >= 85:
        return '85-100 (强烈买入)'
    elif score >= 70:
        return '70-84 (买入)'
    elif score >= 60:
        return '60-69 (谨慎买入)'
    elif score >= 50:
        return '50-59 (观望)'
    else:
        return '<50 (不推荐)'

def analyze_signal_effectiveness(archives: List[Dict], tracking: List[Dict]) -> Dict:
    """分析信号组合的有效性"""
    results = {
        'by_buy_signals': defaultdict(lambda: {'total': 0, 'wins': 0, 'avg_return': 0}),
        'by_sell_signals': defaultdict(lambda: {'total': 0, 'wins': 0, 'avg_return': 0}),
        'by_confluence': defaultdict(lambda: {'total': 0, 'wins': 0, 'avg_return': 0}),
    }
    
    tracking_map = {t['code']: t for t in tracking}
    
    for archive in archives:
        code = archive['code']
        buy_signals = archive['buy_signal_count']
        sell_signals = archive['sell_signal_count']
        confluence = archive['confluence_score']
        
        if code in tracking_map:
            track = tracking_map[code]
            actual_return = track.get('day5_return') or track.get('day10_return') or track.get('day20_return')
            
            if actual_return is not None:
                # 按买入信号数量统计
                results['by_buy_signals'][buy_signals]['total'] += 1
                results['by_buy_signals'][buy_signals]['avg_return'] += actual_return
                if actual_return > 0:
                    results['by_buy_signals'][buy_signals]['wins'] += 1
                
                # 按卖出信号数量统计
                results['by_sell_signals'][sell_signals]['total'] += 1
                results['by_sell_signals'][sell_signals]['avg_return'] += actual_return
                if actual_return > 0:
                    results['by_sell_signals'][sell_signals]['wins'] += 1
                
                # 按共振分数统计
                confluence_range = get_confluence_range(confluence)
                results['by_confluence'][confluence_range]['total'] += 1
                results['by_confluence'][confluence_range]['avg_return'] += actual_return
                if actual_return > 0:
                    results['by_confluence'][confluence_range]['wins'] += 1
    
    # 计算平均收益和胜率
    for category in results:
        for key in results[category]:
            data = results[category][key]
            if data['total'] > 0:
                data['avg_return'] = data['avg_return'] / data['total']
                data['win_rate'] = (data['wins'] / data['total']) * 100
            else:
                data['avg_return'] = 0
                data['win_rate'] = 0
    
    return results

def get_confluence_range(confluence: int) -> str:
    """将共振分数转换为区间"""
    if confluence >= 80:
        return '80-100 (强共振)'
    elif confluence >= 60:
        return '60-79 (中共振)'
    elif confluence >= 40:
        return '40-59 (弱共振)'
    else:
        return '<40 (无共振)'

def generate_optimization_suggestions(accuracy_results: Dict, signal_results: Dict) -> List[str]:
    """生成优化建议"""
    suggestions = []
    
    # 分析推荐类型胜率
    rec_stats = accuracy_results['by_recommendation']
    if '强烈买入' in rec_stats and rec_stats['强烈买入']['win_rate'] < 60:
        suggestions.append("⚠️ 强烈买入推荐胜率低于60%，建议提高评分阈值或增加信号确认条件")
    
    if '买入' in rec_stats and rec_stats['买入']['win_rate'] < 55:
        suggestions.append("⚠️ 买入推荐胜率偏低，考虑调整70-84分段的推荐逻辑")
    
    # 分析评分区间表现
    score_stats = accuracy_results['by_score_range']
    high_score_range = '85-100 (强烈买入)'
    if high_score_range in score_stats and score_stats[high_score_range]['avg_return'] < 2:
        suggestions.append("⚠️ 高评分(85+)股票平均收益偏低，可能存在评分虚高问题")
    
    # 分析信号数量与收益关系
    buy_signal_stats = signal_results['by_buy_signals']
    if 3 in buy_signal_stats and buy_signal_stats[3]['win_rate'] < 50:
        suggestions.append("⚠️ 3个买入信号的胜率偏低，建议优化信号权重或增加信号质量筛选")
    
    # 分析共振分数效果
    confluence_stats = signal_results['by_confluence']
    high_confluence = '80-100 (强共振)'
    if high_confluence in confluence_stats and confluence_stats[high_confluence]['win_rate'] < 65:
        suggestions.append("⚠️ 强共振股票胜率未达预期，考虑调整共振计算逻辑")
    
    # 分析高风险案例
    if len(accuracy_results['high_score_failures']) > 5:
        suggestions.append(f"⚠️ 发现{len(accuracy_results['high_score_failures'])}个高评分但大幅亏损案例，建议增加止损信号")
    
    # 分析低风险机会
    if len(accuracy_results['low_score_successes']) > 3:
        suggestions.append(f"💡 发现{len(accuracy_results['low_score_successes'])}个低评分但大幅盈利案例，可能存在评分遗漏的利好因素")
    
    # 通用建议
    if not suggestions:
        suggestions.append("✅ 当前评分机制表现良好，建议继续监控并积累更多数据")
    
    return suggestions

def generate_report(archives: List[Dict], tracking: List[Dict], accuracy_results: Dict, 
                   signal_results: Dict, suggestions: List[str]) -> str:
    """生成Markdown格式的分析报告"""
    report_date = datetime.now().strftime('%Y-%m-%d %H:%M')
    
    report = f"""# 评分机制准确性分析报告

生成时间: {report_date}

## 数据概览

- 分析留档记录数: {len(archives)}
- 有收益追踪的记录数: {len(tracking)}
- 分析时间范围: 最近30天

## 一、推荐类型准确性分析

| 推荐类型 | 样本数 | 胜率 | 平均收益 |
|---------|--------|------|----------|
"""
    
    for rec_type in ['强烈买入', '买入', '谨慎买入', '观望', '谨慎卖出', '卖出', '强烈卖出']:
        if rec_type in accuracy_results['by_recommendation']:
            stats = accuracy_results['by_recommendation'][rec_type]
            report += f"| {rec_type} | {stats['total']} | {stats['win_rate']:.1f}% | {stats['avg_return']:.2f}% |\n"
    
    report += """
## 二、评分区间表现分析

| 评分区间 | 样本数 | 胜率 | 平均收益 |
|---------|--------|------|----------|
"""
    
    for score_range in ['85-100 (强烈买入)', '70-84 (买入)', '60-69 (谨慎买入)', '50-59 (观望)', '<50 (不推荐)']:
        if score_range in accuracy_results['by_score_range']:
            stats = accuracy_results['by_score_range'][score_range]
            report += f"| {score_range} | {stats['total']} | {stats['win_rate']:.1f}% | {stats['avg_return']:.2f}% |\n"
    
    report += """
## 三、风险等级表现分析

| 风险等级 | 样本数 | 胜率 | 平均收益 |
|---------|--------|------|----------|
"""
    
    for risk_level in ['低风险', '中风险', '高风险']:
        if risk_level in accuracy_results['by_risk_level']:
            stats = accuracy_results['by_risk_level'][risk_level]
            report += f"| {risk_level} | {stats['total']} | {stats['win_rate']:.1f}% | {stats['avg_return']:.2f}% |\n"
    
    report += """
## 四、信号组合有效性分析

### 4.1 买入信号数量与收益关系

| 买入信号数 | 样本数 | 胜率 | 平均收益 |
|-----------|--------|------|----------|
"""
    
    for signals in sorted(signal_results['by_buy_signals'].keys()):
        stats = signal_results['by_buy_signals'][signals]
        report += f"| {signals} | {stats['total']} | {stats['win_rate']:.1f}% | {stats['avg_return']:.2f}% |\n"
    
    report += """
### 4.2 共振分数与收益关系

| 共振分数区间 | 样本数 | 胜率 | 平均收益 |
|-------------|--------|------|----------|
"""
    
    for confluence_range in ['80-100 (强共振)', '60-79 (中共振)', '40-59 (弱共振)', '<40 (无共振)']:
        if confluence_range in signal_results['by_confluence']:
            stats = signal_results['by_confluence'][confluence_range]
            report += f"| {confluence_range} | {stats['total']} | {stats['win_rate']:.1f}% | {stats['avg_return']:.2f}% |\n"
    
    report += """
## 五、异常案例分析

### 5.1 高评分但大幅亏损案例（评分≥80，收益<-3%）

"""
    
    if accuracy_results['high_score_failures']:
        report += "| 日期 | 代码 | 名称 | 评分 | 推荐 | 收益 |\n"
        report += "|------|------|------|------|------|------|\n"
        for case in accuracy_results['high_score_failures'][:10]:  # 只显示前10个
            report += f"| {case['date']} | {case['code']} | {case['name']} | {case['score']} | {case['recommendation']} | {case['return']:.2f}% |\n"
    else:
        report += "✅ 未发现高评分但大幅亏损的案例\n"
    
    report += """
### 5.2 低评分但大幅盈利案例（评分<60，收益>5%）

"""
    
    if accuracy_results['low_score_successes']:
        report += "| 日期 | 代码 | 名称 | 评分 | 推荐 | 收益 |\n"
        report += "|------|------|------|------|------|------|\n"
        for case in accuracy_results['low_score_successes'][:10]:  # 只显示前10个
            report += f"| {case['date']} | {case['code']} | {case['name']} | {case['score']} | {case['recommendation']} | {case['return']:.2f}% |\n"
    else:
        report += "✅ 未发现低评分但大幅盈利的案例\n"
    
    report += """
## 六、优化建议

"""
    
    for i, suggestion in enumerate(suggestions, 1):
        report += f"{i}. {suggestion}\n"
    
    report += """
## 七、结论

"""
    
    # 计算整体胜率和平均收益
    total_samples = sum(stats['total'] for stats in accuracy_results['by_recommendation'].values())
    total_wins = sum(stats['wins'] for stats in accuracy_results['by_recommendation'].values())
    overall_win_rate = (total_wins / total_samples * 100) if total_samples > 0 else 0
    
    total_return = sum(stats['avg_return'] * stats['total'] for stats in accuracy_results['by_recommendation'].values())
    overall_avg_return = (total_return / total_samples) if total_samples > 0 else 0
    
    report += f"""
### 整体表现

- **整体胜率**: {overall_win_rate:.1f}%
- **平均收益**: {overall_avg_return:.2f}%
- **样本总数**: {total_samples}

### 评价标准

- 胜率 > 60%: ✅ 优秀
- 胜率 50-60%: ⚠️ 良好但需优化
- 胜率 < 50%: ❌ 需要重大改进

"""
    
    if overall_win_rate >= 60:
        report += "✅ 当前评分机制整体表现优秀，建议继续保持并积累更多数据\n"
    elif overall_win_rate >= 50:
        report += "⚠️ 当前评分机制表现良好，但存在优化空间，建议根据上述建议进行调整\n"
    else:
        report += "❌ 当前评分机制胜率偏低，建议重点优化评分逻辑和推荐阈值\n"
    
    report += f"""
---

*本报告由自动化分析脚本生成，建议结合实际情况进行人工审核*
"""
    
    return report

def main():
    """主函数"""
    print("开始分析评分机制准确性...")
    
    try:
        # 连接数据库
        conn = get_db_connection()
        print(f"✓ 数据库连接成功: {DB_PATH}")
        
        # 获取数据
        print("正在获取留档记录...")
        archives = fetch_archive_records(conn, days_back=30)
        print(f"✓ 获取到 {len(archives)} 条留档记录")
        
        print("正在获取推荐追踪数据...")
        tracking = fetch_recommendation_tracking(conn, days_back=30)
        print(f"✓ 获取到 {len(tracking)} 条追踪记录")
        
        if len(archives) == 0:
            print("⚠️ 没有留档记录，无法进行分析")
            return
        
        if len(tracking) == 0:
            print("⚠️ 没有推荐追踪数据，分析结果可能不完整")
        
        # 分析推荐准确性
        print("正在分析推荐准确性...")
        accuracy_results = analyze_recommendation_accuracy(archives, tracking)
        
        # 分析信号有效性
        print("正在分析信号有效性...")
        signal_results = analyze_signal_effectiveness(archives, tracking)
        
        # 生成优化建议
        print("正在生成优化建议...")
        suggestions = generate_optimization_suggestions(accuracy_results, signal_results)
        
        # 生成报告
        print("正在生成分析报告...")
        report = generate_report(archives, tracking, accuracy_results, signal_results, suggestions)
        
        # 保存报告
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, 'w', encoding='utf-8') as f:
            f.write(report)
        
        print(f"✓ 分析报告已保存: {REPORT_PATH}")
        print("\n分析完成！")
        
        conn.close()
        
    except Exception as e:
        print(f"❌ 分析失败: {e}")
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    main()
