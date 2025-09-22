"""환경 설정 관리 모듈 - 노트북 코드 그대로 모듈화"""
import os

from dotenv import load_dotenv
from langchain_teddynote import logging

# API KEY 정보 로드 (노트북 코드 그대로)
load_dotenv()

# 프로젝트 이름을 입력합니다.
logging.langsmith("=== 01.Simple-RAG-Practice ===")

# 데이터베이스 연결 설정 값들 (노트북 코드 그대로)
USER = os.getenv("POSTGRES_USER", "user")
PASSWORD = os.getenv("POSTGRES_PASSWORD", "password")
HOST = os.getenv("POSTGRES_HOST", "host")
DATABASE = os.getenv("POSTGRES_DB", "database")
PORT = os.getenv("POSTGRES_PORT", "5432")

# 임베딩 설정 (노트북 코드 그대로)
embedding_provider = os.getenv("EMBEDDING_PROVIDER", "upstage")
embedding_model = os.getenv("EMBEDDING_MODEL", "embedding-query")
# 문자열을 정수로 변환 (노트북 코드 그대로)
embedding_dimensions = int(os.getenv("EMBEDDING_DIMENSIONS", "1536"))
