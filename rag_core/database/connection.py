# -*- coding: utf-8 -*-
"""데이터베이스 연결 설정 - 노트북 코드 그대로 모듈화"""

from sqlalchemy import create_engine, URL
from sqlalchemy.orm import sessionmaker

from ..config import USER, PASSWORD, HOST, DATABASE

# 연결 URL 구성 (노트북 코드 그대로)
DATABASE_URL = URL.create(
    "postgresql+psycopg2",
    username=USER,
    password=PASSWORD,
    host=HOST,
    database=DATABASE
)

# 엔진 생성 (노트북 코드 그대로)
engine = create_engine(DATABASE_URL)

# SessionLocal 팩토리 생성 (노트북 코드 그대로)
SessionLocal = sessionmaker(
    bind=engine,
    autocommit=False,  # 자동 커밋 비활성화
    autoflush=True,  # 자동 플러시 활성화
    expire_on_commit=True,  # 커밋 후 객체 만료
)
