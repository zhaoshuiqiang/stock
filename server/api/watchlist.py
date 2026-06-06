"""关注列表 API"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from server.db.database import get_db
from server.models.models import Watchlist
from server.models.schemas import WatchlistItem, WatchlistCreate

router = APIRouter()


@router.get("/watchlist", response_model=List[WatchlistItem])
async def list_watchlist(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Watchlist).order_by(Watchlist.added_at.desc()))
    items = result.scalars().all()
    return [WatchlistItem(code=item.code, name=item.name, added_at=item.added_at) for item in items]


@router.post("/watchlist", response_model=WatchlistItem)
async def add_watchlist(body: WatchlistCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Watchlist).where(Watchlist.code == body.code))
    existing = result.scalar_one_or_none()
    if existing:
        raise HTTPException(status_code=409, detail=f"股票 {body.code} 已在关注列表中")

    item = Watchlist(code=body.code, name=body.name)
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return WatchlistItem(code=item.code, name=item.name, added_at=item.added_at)


@router.delete("/watchlist/{code}")
async def remove_watchlist(code: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Watchlist).where(Watchlist.code == code))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail=f"股票 {code} 不在关注列表中")

    await db.delete(item)
    await db.commit()
    return {"message": f"已移除 {code}", "code": code}