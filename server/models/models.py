"""数据库模型定义"""
from sqlalchemy import Column, Integer, String, Float, DateTime, Boolean, Text, create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from datetime import datetime
import os
import json

from server.config import DATABASE_URL_SYNC, BASE_DIR


class Base(DeclarativeBase):
    pass


class Watchlist(Base):
    __tablename__ = "watchlist"
    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String(20), nullable=False, unique=True)
    name = Column(String(100), nullable=False)
    added_at = Column(DateTime, default=datetime.now)


class AlertRule(Base):
    __tablename__ = "alert_rules"
    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String(20), nullable=False)
    name = Column(String(100), nullable=False)
    alert_type = Column(String(50), nullable=False)     # price_up / price_down / pct_up / pct_down / indicator
    threshold = Column(Float, nullable=True)             # 阈值
    indicator_type = Column(String(50), nullable=True)   # 技术指标类型（如 macd_golden_cross）
    enabled = Column(Boolean, default=True)
    last_triggered = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.now)


class AnalysisCache(Base):
    __tablename__ = "analysis_cache"
    id = Column(Integer, primary_key=True, autoincrement=True)
    code = Column(String(20), nullable=False)
    cache_type = Column(String(50), nullable=False)  # quote / history / analysis / sentiment
    data = Column(Text, nullable=False)
    updated_at = Column(DateTime, default=datetime.now)


def init_db():
    """初始化数据库并创建表"""
    engine = create_engine(DATABASE_URL_SYNC)
    Base.metadata.create_all(engine)
    return engine


def migrate_watchlist():
    """将现有 watchlist.json 数据迁移到数据库"""
    watchlist_path = os.path.join(os.path.dirname(BASE_DIR), "watchlist.json")
    if os.path.exists(watchlist_path):
        try:
            with open(watchlist_path, "r", encoding="utf-8") as f:
                items = json.load(f)
            engine = create_engine(DATABASE_URL_SYNC)
            Session = sessionmaker(bind=engine)
            session = Session()
            for item in items:
                parts = item.split(" - ", 1)
                code = parts[0].strip()
                name = parts[1].strip() if len(parts) > 1 else code
                existing = session.query(Watchlist).filter_by(code=code).first()
                if not existing:
                    session.add(Watchlist(code=code, name=name))
            session.commit()
            session.close()
            print(f"已迁移 {len(items)} 条关注记录")
        except Exception as e:
            print(f"迁移失败：{e}")