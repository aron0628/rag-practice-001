# -*- coding: utf-8 -*-
"""임베딩 제공자 관리 - 노트북 코드 그대로 모듈화"""

from langchain_openai import OpenAIEmbeddings
from langchain_upstage import UpstageEmbeddings

from ..config import embedding_provider, embedding_model, embedding_dimensions

# 노트북 코드 그대로 - 기본 OpenAI로 초기화
embeddings = OpenAIEmbeddings(model=embedding_model)

if embedding_provider == "upstage":
    # UpstageEmbedding 모델 차원수 조정 및 선언
    embeddings = UpstageEmbeddings(
        model=embedding_model,
        dimensions=4096 if embedding_dimensions == 4000 else embedding_dimensions
    )


def get_embeddings():
    """현재 설정된 임베딩 모델 반환"""
    return embeddings
