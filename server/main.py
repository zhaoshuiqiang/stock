"""FastAPI 主应用入口"""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from server.db.database import engine
from server.models.models import Base, init_db, migrate_watchlist
from server.api import watchlist, alerts, market, analysis, websocket


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动时初始化数据库
    init_db()
    migrate_watchlist()
    yield
    # 关闭时清理
    await engine.dispose()


app = FastAPI(
    title="增强型股票分析系统 API",
    description="提供实时行情、技术分析、盯盘提醒等服务的 REST API",
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(watchlist.router, prefix="/api", tags=["关注列表"])
app.include_router(alerts.router, prefix="/api", tags=["盯盘提醒"])
app.include_router(market.router, prefix="/api", tags=["行情数据"])
app.include_router(analysis.router, prefix="/api", tags=["技术分析"])
app.include_router(websocket.router, prefix="/ws", tags=["实时推送"])


@app.get("/")
async def root():
    return {"message": "增强型股票分析系统 API v2.0", "status": "running"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server.main:app", host="0.0.0.0", port=8000, reload=True)