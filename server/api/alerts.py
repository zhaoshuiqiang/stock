"""盯盘提醒 API"""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List

from server.db.database import get_db
from server.models.models import AlertRule
from server.models.schemas import AlertRuleCreate, AlertRuleUpdate, AlertRuleResponse

router = APIRouter()


@router.get("/alerts", response_model=List[AlertRuleResponse])
async def list_alerts(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AlertRule).order_by(AlertRule.created_at.desc()))
    items = result.scalars().all()
    return [
        AlertRuleResponse(
            id=item.id,
            code=item.code,
            name=item.name,
            alert_type=item.alert_type,
            threshold=item.threshold,
            indicator_type=item.indicator_type,
            enabled=item.enabled,
            last_triggered=item.last_triggered,
            created_at=item.created_at,
        )
        for item in items
    ]


@router.post("/alerts", response_model=AlertRuleResponse)
async def create_alert(body: AlertRuleCreate, db: AsyncSession = Depends(get_db)):
    item = AlertRule(
        code=body.code,
        name=body.name,
        alert_type=body.alert_type,
        threshold=body.threshold,
        indicator_type=body.indicator_type,
    )
    db.add(item)
    await db.commit()
    await db.refresh(item)
    return AlertRuleResponse(
        id=item.id,
        code=item.code,
        name=item.name,
        alert_type=item.alert_type,
        threshold=item.threshold,
        indicator_type=item.indicator_type,
        enabled=item.enabled,
        last_triggered=item.last_triggered,
        created_at=item.created_at,
    )


@router.put("/alerts/{alert_id}", response_model=AlertRuleResponse)
async def update_alert(alert_id: int, body: AlertRuleUpdate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AlertRule).where(AlertRule.id == alert_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail=f"提醒规则 {alert_id} 不存在")

    if body.enabled is not None:
        item.enabled = body.enabled
    if body.threshold is not None:
        item.threshold = body.threshold

    await db.commit()
    await db.refresh(item)
    return AlertRuleResponse(
        id=item.id,
        code=item.code,
        name=item.name,
        alert_type=item.alert_type,
        threshold=item.threshold,
        indicator_type=item.indicator_type,
        enabled=item.enabled,
        last_triggered=item.last_triggered,
        created_at=item.created_at,
    )


@router.delete("/alerts/{alert_id}")
async def delete_alert(alert_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(AlertRule).where(AlertRule.id == alert_id))
    item = result.scalar_one_or_none()
    if not item:
        raise HTTPException(status_code=404, detail=f"提醒规则 {alert_id} 不存在")

    await db.delete(item)
    await db.commit()
    return {"message": f"已删除提醒规则 {alert_id}", "id": alert_id}