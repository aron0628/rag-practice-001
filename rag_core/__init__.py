# -*- coding: utf-8 -*-
"""RAG Core - 재사용 가능한 RAG 컴포넌트"""

__version__ = "0.1.0"

# 설정 관련
from .config import (
    USER, PASSWORD, HOST, DATABASE, PORT,
    embedding_provider, embedding_model, embedding_dimensions
)

# 데이터베이스 관련
from .database import engine, SessionLocal, DATABASE_URL

# 모델 관련
from .models import Base, File, Document

# 임베딩 관련
from .embeddings import embeddings, get_embeddings

# 검색 관련
from .retrievers import DenseRetriever

# 전체 export 목록
__all__ = [
    # 버전
    "__version__",

    # 설정
    "USER", "PASSWORD", "HOST", "DATABASE", "PORT",
    "embedding_provider", "embedding_model", "embedding_dimensions",

    # 데이터베이스
    "engine", "SessionLocal", "DATABASE_URL",

    # 모델
    "Base", "File", "Document",

    # 임베딩
    "embeddings", "get_embeddings",

    # 검색
    "DenseRetriever",
]