# -*- coding: utf-8 -*-
"""SQLAlchemy ORM 모델 정의 - 노트북 코드 그대로 모듈화"""

from pgvector.sqlalchemy import Vector, HALFVEC
from sqlalchemy import Column, BigInteger, Text, Integer, CHAR, JSON, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import declarative_base, relationship
from sqlalchemy.sql import func

from ..config import embedding_dimensions

Base = declarative_base()
suffix = "" if embedding_dimensions == 2000 else f"_{embedding_dimensions}"
vector_type = HALFVEC(embedding_dimensions) if embedding_dimensions == 4000 else Vector(embedding_dimensions)


class File(Base):
    """파일 정보 테이블 - 노트북 코드 그대로"""
    __tablename__ = f"files{suffix}"
    __table_args__ = {'schema': 'rag'}  # 스키마가 있다면 지정

    # uuid with default as primary key
    id = Column(UUID(as_uuid=True), primary_key=True,
                server_default=func.gen_random_uuid())

    # text not null
    file_path = Column(Text, nullable=False)

    # char(40) not null
    file_sha1 = Column(CHAR(40), nullable=False)

    # text (nullable)
    source = Column(Text)

    # timestamps with defaults
    created_at = Column(DateTime, server_default=func.CURRENT_TIMESTAMP())
    updated_at = Column(DateTime, server_default=func.CURRENT_TIMESTAMP(),
                        onupdate=func.CURRENT_TIMESTAMP())

    # 1:N relationship with documents
    documents = relationship("Document", back_populates="file", cascade="all, delete-orphan")


class Document(Base):
    """문서 정보 테이블 - 노트북 코드 그대로"""
    __tablename__ = f"documents{suffix}"
    __table_args__ = {'schema': 'rag'}  # 스키마가 있다면 지정

    # bigserial primary key
    id = Column(BigInteger, primary_key=True, autoincrement=True)

    # uuid with foreign key (수정된 부분)
    file_id = Column(UUID(as_uuid=True), ForeignKey(f"rag.files{suffix}.id", ondelete='CASCADE'))

    # uuid with default
    document_id = Column(UUID(as_uuid=True), server_default=func.gen_random_uuid())

    # text not null
    content = Column(Text, nullable=False)

    # char(40) not null
    sha1 = Column(CHAR(40), nullable=False)

    # integers (nullable)
    chunk_index = Column(Integer)
    page_start = Column(Integer)
    page_end = Column(Integer)
    page_number = Column(Integer)
    token_count = Column(Integer)

    # text (nullable)
    section_title = Column(Text)

    # jsonb
    doc_metadata = Column('metadata', JSON)

    # vector - Integer() 제거하고 차원수만 직접 전달
    embedding = Column(vector_type)

    # timestamps with defaults
    created_at = Column(DateTime, server_default=func.CURRENT_TIMESTAMP())
    updated_at = Column(DateTime, server_default=func.CURRENT_TIMESTAMP(), onupdate=func.CURRENT_TIMESTAMP())

    # relationship (수정된 부분)
    file = relationship("File", back_populates="documents")
