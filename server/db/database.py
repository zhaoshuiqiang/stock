"""数据库会话管理"""
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from server.config import DATABASE_URL

engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session