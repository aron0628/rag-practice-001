# -*- coding: utf-8 -*-
"""설정 관리 모듈"""

from .settings import (
    USER, PASSWORD, HOST, DATABASE, PORT,
    embedding_provider, embedding_model, embedding_dimensions
)

__all__ = [
    "USER", "PASSWORD", "HOST", "DATABASE", "PORT",
    "embedding_provider", "embedding_model", "embedding_dimensions"
]