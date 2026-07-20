#!/usr/bin/env python3
# -*- coding: gbk -*-
"""留档 CSV 加载器。

把 留档数据/archive_export_*.csv（10 个）解析为统一面板：
  - 去重股票池（universe）
  - 归档面板（code、归档时间、App 评分/推荐/共振评分/买卖信号数/topSignals ...）

归档时间保留完整时间戳；"信息可得的 as-of 交易日"（考虑 15:00 收盘规则、
避免前视）在与 K 线 join 时再解析（见 compare_app_score.py / backtest.py）。
"""

import glob
import os

import pandas as pd

import config

# 中文列名 -> 英文键
_COL_MAP = {
    '代码': 'code',
    '名称': 'name',
    '留档价格': 'archive_price',
    '留档涨跌幅(%)': 'archive_change_pct',
    '评分': 'app_score',
    '推荐': 'recommendation',
    '风险等级': 'risk_level',
    '买入信号数': 'buy_signals',
    '卖出信号数': 'sell_signals',
    '活跃战法数': 'active_strategies',
    '共振评分': 'confluence_score',
    '留档时间': 'archive_time',
    '现价': 'export_price',
    '现涨跌幅(%)': 'export_change_pct',
    '价格变动(%)': 'price_change_pct',
    '是否偏差': 'is_deviation',
    '可靠性': 'reliability',
    'topSignals': 'top_signals',
}

_NUMERIC_COLS = [
    'archive_price', 'archive_change_pct', 'app_score', 'buy_signals',
    'sell_signals', 'active_strategies', 'confluence_score', 'export_price',
    'export_change_pct', 'price_change_pct',
]

_VALID_PREFIXES = ('sh', 'sz', 'bj')


def _normalize_code(raw) -> str:
    """归一化股票代码为小写带前缀形式（sh600519）。无法识别返回空串。"""
    if raw is None:
        return ''
    s = str(raw).strip().lower()
    if s.startswith(_VALID_PREFIXES):
        return s
    # 纯数字：按首位推断交易所（6->sh, 0/3->sz, 4/8->bj）
    digits = ''.join(ch for ch in s if ch.isdigit())
    if len(digits) == 6:
        if digits[0] == '6':
            return 'sh' + digits
        if digits[0] in ('0', '3'):
            return 'sz' + digits
        if digits[0] in ('4', '8'):
            return 'bj' + digits
    return ''


def load_archive_panel(archive_dir: str = None) -> pd.DataFrame:
    """读取全部留档 CSV，返回统一面板 DataFrame。"""
    archive_dir = archive_dir or config.ARCHIVE_DIR
    pattern = os.path.join(archive_dir, 'archive_export_*.csv')
    files = sorted(glob.glob(pattern))
    if not files:
        raise FileNotFoundError(f'未找到留档 CSV: {pattern}')

    frames = []
    for path in files:
        # utf-8-sig 兼容可能的 BOM
        df = pd.read_csv(path, encoding='utf-8-sig', dtype=str)
        df = df.rename(columns={k: v for k, v in _COL_MAP.items() if k in df.columns})
        if 'code' not in df.columns:
            continue
        df['code'] = df['code'].map(_normalize_code)
        df = df[df['code'] != '']
        for col in _NUMERIC_COLS:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')
        # 归档时间戳
        df['archive_time'] = pd.to_datetime(df['archive_time'], errors='coerce')
        df['archive_date'] = df['archive_time'].dt.normalize()
        df['source_file'] = os.path.basename(path)
        frames.append(df)

    panel = pd.concat(frames, ignore_index=True)
    panel = panel.dropna(subset=['archive_time'])
    # 同一 (code, 归档日) 若重复，保留后出现的一条（一般不会重复）
    panel = panel.sort_values(['archive_time', 'code']).reset_index(drop=True)
    return panel


def get_universe(panel: pd.DataFrame) -> list:
    """去重后的股票代码列表（已排序）。"""
    return sorted(panel['code'].dropna().unique().tolist())


def _summary(panel: pd.DataFrame) -> str:
    lines = []
    files = sorted(panel['source_file'].unique().tolist())
    dates = sorted(panel['archive_date'].dropna().dt.strftime('%Y-%m-%d').unique().tolist())
    uni = get_universe(panel)
    lines.append(f'留档文件数: {len(files)}')
    lines.append(f'归档记录总行数: {len(panel)}')
    lines.append(f'去重股票数(universe): {len(uni)}')
    lines.append(f'归档日期: {dates[0]} ~ {dates[-1]}（共 {len(dates)} 个）')
    # 前缀分布
    pref = pd.Series([c[:2] for c in uni]).value_counts().to_dict()
    lines.append(f'交易所前缀分布: {pref}')
    # 推荐分布
    if 'recommendation' in panel.columns:
        rec = panel['recommendation'].value_counts().to_dict()
        lines.append(f'推荐分布: {rec}')
    # 每文件行数
    per_file = panel.groupby('source_file').size().to_dict()
    lines.append('每文件行数:')
    for f in files:
        lines.append(f'  {f}: {per_file.get(f, 0)}')
    return '\n'.join(lines)


def main():
    config.force_utf8_stdout()
    config.ensure_dirs()
    panel = load_archive_panel()
    print(_summary(panel))
    out = os.path.join(config.OUTPUT_DIR, 'archive_panel.csv')
    panel.to_csv(out, index=False, encoding='utf-8-sig')
    print(f'\n归档面板已保存: {out}')
    # 股票池清单
    uni = get_universe(panel)
    uni_path = os.path.join(config.OUTPUT_DIR, 'universe.txt')
    with open(uni_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(uni))
    print(f'股票池清单已保存: {uni_path}（{len(uni)} 只）')


if __name__ == '__main__':
    config.add_self_to_path()
    main()
