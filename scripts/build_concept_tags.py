#!/usr/bin/env python3
"""
概念标签数据生成脚本
使用 akshare 获取概念板块和成分股数据，生成 concept_tags.json

用法: python scripts/build_concept_tags.py
输出: mobile/assets/concept_tags.json
"""

import json
import os
import time
import sys
from typing import Dict, List, Set

try:
    import akshare as ak
except ImportError:
    print("请先安装 akshare: pip install akshare")
    sys.exit(1)

# 长线概念分类: 战略性/产业趋势类
LONG_TERM_CONCEPTS: Set[str] = {
    "新材料", "芯片概念", "半导体", "人工智能", "AI", "机器人",
    "新能源汽车", "锂电池", "钠离子电池", "固态电池", "氢能源",
    "光伏", "风电", "核能", "储能",
    "军工", "航空航天", "大飞机", "商业航天",
    "智能制造", "工业互联网", "数字孪生", "工业母机",
    "汽车芯片", "IGBT", "第三代半导体", "光刻机", "光刻胶",
    "量子通信", "6G概念", "5G", "卫星导航", "低空经济",
    "数字经济", "信创", "东数西算", "东数西算概念",
    "碳中和", "碳达峰", "绿色电力", "节能环保",
    "医疗器械", "创新药", "生物医药", "基因测序", "辅助生殖",
    "食品安全", "粮食安全", "种业", "农业种植",
    "一带一路", "国企改革", "中字头", "中特估",
    "消费电子", "虚拟现实", "增强现实", "元宇宙",
    "中芯国际概念", "华为概念", "鸿蒙概念", "欧拉",
    "数据要素", "算力", "CPO", "先进封装", "Chiplet",
    "人形机器人", "脑机接口", "飞行汽车", "可控核聚变",
    "液冷服务器", "铜缆高速连接", "高速连接器",
    "海洋经济", "深海科技", "商业航天",
    "冰雪产业", "电竞", "电子竞技",
}

# 短线概念分类: 事件驱动/题材类
SHORT_TERM_CONCEPTS: Set[str] = {
    "涨价", "涨价概念", "涨价题材", "业绩预增", "高送转",
    "ST", "*ST概念", "壳资源", "举牌", "重组",
    "数字货币", "区块链", "Web3", "NFT",
    "预制菜", "社区团购", "地摊经济", "网红直播", "盲盒",
    "在线教育", "远程办公", "疫情防控", "口罩", "检测试剂",
    "出口管制", "稀土永磁", "小金属", "黄金概念",
    "有色", "煤炭", "电力", "化工", "钢铁",
    "旅游", "酒店餐饮", "景点", "影视", "文化传媒",
    "房地产", "基建", "水泥", "建材", "装修装饰",
    "白酒", "啤酒", "乳业", "预制菜", "食品加工",
    "医药商业", "中药", "化学制药",
    "跨境电商", "统一大市场", "物流",
    "数字货币", "跨境支付", "移动支付",
    "海南自贸区", "雄安新区", "深圳本地", "上海本地",
    "摘帽", "业绩承诺", "回购", "增持", "股权激励",
    "IPO受益", "定增", "配股",
    "血制品", "疫苗", "流感", "肺炎",
    "彩票", "博彩", "游戏", "网络游戏",
    "军工信息化", "军民融合",
    "猪肉", "鸡肉", "养殖业",
    "小金属", "稀土", "钨", "钼",
    "天然气", "页岩气", "油气改革",
    "国资委", "央企改革", "地方国资",
}


def classify_concept(name: str) -> str:
    """将概念分类为 long/short/general"""
    # 精确匹配
    if name in LONG_TERM_CONCEPTS:
        return "long"
    if name in SHORT_TERM_CONCEPTS:
        return "short"

    # 模糊匹配
    name_lower = name.lower().replace("概念", "")
    for kw in ["新能源", "新材料", "芯片", "半导体", "军工", "医药", "生物",
               "机器人", "人工智能", "航天", "量子", "光刻", "储能",
               "算力", "封装", "cpo", "chiplet", "信创", "数字经济",
               "车联网", "自动驾驶", "物联网", "碳中和", "智能制造"]:
        if kw.lower() in name_lower:
            return "long"

    for kw in ["涨价", "预增", "重组", "举牌", "壳资源", "st板块",
               "海南", "雄安", "自贸区", "回购", "增持", "摘帽",
               "网络游戏", "直播", "盲盒", "预制菜", "口罩",
               "检测", "疫苗", "血制品", "猪肉", "鸡肉"]:
        if kw.lower() in name_lower:
            return "short"

    # 默认归类
    return "long"  # 大部分概念偏向长线


def fetch_concept_data(max_concepts: int = 300) -> Dict[str, Dict[str, List[str]]]:
    """
    获取概念数据并构建股票->概念映射
    返回: { "000001.SZ": {"long": ["概念A"], "short": ["概念B"]}, ... }
    """
    stock_concepts: Dict[str, Dict[str, List[str]]] = {}

    print(f"[1/2] 获取概念板块列表...")
    for attempt in range(3):
        try:
            concept_df = ak.stock_board_concept_name_em()
            print(f"  获取到 {len(concept_df)} 个概念板块")
            break
        except Exception as e:
            print(f"  尝试 {attempt+1}/3 失败: {e}")
            time.sleep(3)
    else:
        print("  无法获取概念板块列表，请检查网络连接")
        return stock_concepts

    # 限制数量
    if len(concept_df) > max_concepts:
        concept_df = concept_df.head(max_concepts)

    print(f"[2/2] 获取各概念成分股...")
    success_count = 0
    for idx, row in concept_df.iterrows():
        name = row.get("概念名称") or row.get("板块名称") or ""
        code = row.get("概念代码") or row.get("板块代码") or ""

        if not name or not code:
            continue

        concept_type = classify_concept(name)

        try:
            cons_df = ak.stock_board_concept_cons_em(symbol=name)
            if cons_df is None or cons_df.empty:
                continue

            for _, stock in cons_df.iterrows():
                stock_code = stock.get("代码") or stock.get("股票代码") or ""
                stock_name = stock.get("名称") or stock.get("股票名称") or ""

                if not stock_code:
                    continue

                if stock_code not in stock_concepts:
                    stock_concepts[stock_code] = {"long": [], "short": []}

                # 去重
                if name not in stock_concepts[stock_code][concept_type]:
                    stock_concepts[stock_code][concept_type].append(name)

            success_count += 1
            if success_count % 20 == 0:
                print(f"  处理进度: {success_count}/{len(concept_df)}")

        except Exception as e:
            # 单个板块获取失败不影响整体流程
            if success_count < 3:  # 只打印前几个错误
                print(f"  警告: 获取板块 '{name}' 成分股失败: {type(e).__name__}")
            continue

        # 控制速率
        time.sleep(0.5)

    print(f"  成功处理 {success_count} 个概念板块")
    print(f"  覆盖 {len(stock_concepts)} 只股票")

    return stock_concepts


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    output_path = os.path.join(project_dir, "mobile", "assets", "concept_tags.json")

    # 确保输出目录存在
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    print("=" * 50)
    print("概念标签数据生成")
    print("=" * 50)

    data = fetch_concept_data(max_concepts=300)

    if not data:
        print("\n未获取到任何数据，生成空占位文件")
        # 生成最小占位数据以便应用不报错
        placeholder = {
            "_meta": {
                "description": "概念标签数据(占位)",
                "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
                "total_concepts": 0,
                "total_stocks": 0,
                "note": "运行 scripts/build_concept_tags.py 生成完整数据",
            }
        }
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(placeholder, f, ensure_ascii=False, indent=2)
        print(f"占位文件已生成: {output_path}")
        return

    # 统计
    long_count = sum(1 for v in data.values() if v.get("long"))
    short_count = sum(1 for v in data.values() if v.get("short"))

    output = {
        "_meta": {
            "description": "概念标签数据",
            "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "total_stocks": len(data),
            "stocks_with_long": long_count,
            "stocks_with_short": short_count,
        },
    }
    output.update(data)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\n数据已保存到: {output_path}")
    print(f"总股票数: {len(data)}")
    print(f"含长线概念: {long_count}")
    print(f"含短线概念: {short_count}")


if __name__ == "__main__":
    main()
