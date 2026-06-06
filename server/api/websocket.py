"""WebSocket 实时行情推送"""
import asyncio
import json
from typing import Dict, Set

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query

from server.config import WS_PUSH_INTERVAL, WS_HEARTBEAT_INTERVAL

router = APIRouter()


class WebSocketManager:
    """WebSocket 连接管理器"""

    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self.subscriptions: Dict[str, Set[str]] = {}  # user_id -> {codes}
        self._push_task: asyncio.Task | None = None

    async def connect(self, websocket: WebSocket, user_id: str):
        await websocket.accept()
        self.active_connections[user_id] = websocket
        self.subscriptions.setdefault(user_id, set())

    def disconnect(self, user_id: str):
        self.active_connections.pop(user_id, None)
        self.subscriptions.pop(user_id, None)

    def subscribe(self, user_id: str, code: str):
        if user_id in self.subscriptions:
            self.subscriptions[user_id].add(code)

    def unsubscribe(self, user_id: str, code: str):
        if user_id in self.subscriptions:
            self.subscriptions[user_id].discard(code)

    async def send_message(self, user_id: str, message: dict):
        ws = self.active_connections.get(user_id)
        if ws:
            try:
                await ws.send_json(message)
            except Exception:
                self.disconnect(user_id)

    def _get_quote_fn(self):
        try:
            from server.services.data_fetcher import get_realtime_quote
            return get_realtime_quote
        except ImportError:
            return None

    async def push_quotes(self):
        """定时推送所有已订阅股票的行情"""
        get_quote = self._get_quote_fn()
        while True:
            await asyncio.sleep(WS_PUSH_INTERVAL)
            for user_id, codes in list(self.subscriptions.items()):
                if not codes:
                    continue
                for code in list(codes):
                    quote = {}
                    if get_quote:
                        try:
                            quote = await asyncio.to_thread(get_quote, code)
                        except Exception:
                            quote = {"code": code, "error": "获取行情失败"}
                    else:
                        quote = {"code": code, "price": 0, "change_pct": 0}
                    await self.send_message(user_id, {
                        "type": "quote",
                        "code": code,
                        "data": quote,
                    })


manager = WebSocketManager()


@router.websocket("/quote")
async def ws_quote(websocket: WebSocket, user_id: str = Query("default")):
    await manager.connect(websocket, user_id)

    async def heartbeat():
        """心跳发送"""
        while True:
            await asyncio.sleep(WS_HEARTBEAT_INTERVAL)
            try:
                await websocket.send_json({"type": "ping", "timestamp": asyncio.get_running_loop().time()})
            except Exception:
                break

    heartbeat_task = asyncio.create_task(heartbeat())

    # 启动行情推送（仅在首次连接时）
    if manager._push_task is None:
        manager._push_task = asyncio.create_task(manager.push_quotes())

    try:
        while True:
            data = await websocket.receive_json()
            msg_type = data.get("type", "")

            if msg_type == "subscribe":
                code = data.get("code", "")
                if code:
                    manager.subscribe(user_id, code)
                    await manager.send_message(user_id, {
                        "type": "subscribed",
                        "code": code,
                    })

            elif msg_type == "unsubscribe":
                code = data.get("code", "")
                if code:
                    manager.unsubscribe(user_id, code)
                    await manager.send_message(user_id, {
                        "type": "unsubscribed",
                        "code": code,
                    })

            elif msg_type == "pong":
                pass

            elif msg_type == "subscribe_batch":
                codes = data.get("codes", [])
                for code in codes:
                    manager.subscribe(user_id, code)
                await manager.send_message(user_id, {
                    "type": "subscribed_batch",
                    "codes": codes,
                })

    except WebSocketDisconnect:
        pass
    except Exception:
        pass
    finally:
        heartbeat_task.cancel()
        manager.disconnect(user_id)