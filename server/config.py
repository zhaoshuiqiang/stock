"""应用配置"""
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE_URL = f"sqlite+aiosqlite:///{os.path.join(BASE_DIR, 'db', 'stock.db')}"
DATABASE_URL_SYNC = f"sqlite:///{os.path.join(BASE_DIR, 'db', 'stock.db')}"

# 缓存配置
CACHE_TTL_QUOTE = 5       # 行情缓存有效期（秒）
CACHE_TTL_HISTORY = 300   # 历史数据缓存有效期（秒）
CACHE_TTL_SENTIMENT = 60  # 大盘情绪缓存有效期（秒）

# WebSocket 配置
WS_PUSH_INTERVAL = 5      # 行情推送间隔（秒）
WS_HEARTBEAT_INTERVAL = 30  # 心跳间隔（秒）

# 提醒配置
ALERT_COOLDOWN = 300      # 同一提醒冷却时间（秒）