# -*- coding: utf-8 -*-
"""Dense Retriever 구현 - 노트북 코드를 클래스로 구조화"""

from typing import List, Any

from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import embedding_dimensions
from ..embeddings import embeddings
from ..models import Document, File


class DenseRetriever:
    """벡터 유사도 기반 문서 검색기"""

    def __init__(self, session: Session):
        """
        Args:
            session: SQLAlchemy 세션
        """
        self.session = session
        self.embeddings = embeddings
        self.embedding_dimensions = embedding_dimensions

    def search(
            self,
            question: str,
            top_k: int = 20,
            similarity_threshold: float = 0.4,
            min_results: int = 5
    ) -> List[Any]:
        """
        질문에 대한 유사 문서 검색 - 노트북 로직 그대로

        Args:
            question: 검색할 질문
            top_k: 조회할 최대 문서 수
            similarity_threshold: 유사도 임계값
            min_results: 최소 반환 문서 수

        Returns:
            검색 결과 리스트
        """
        # 1. 질문을 임베딩 벡터로 변환
        embedded_query = self.embeddings.embed_query(question)
        embedded_query_4000 = embedded_query[:4000] if self.embedding_dimensions == 4000 else embedded_query

        # 2. 벡터 유사도 검색 쿼리 생성
        similarity = (1 - Document.embedding.cosine_distance(embedded_query_4000))
        query = (
            select(
                File.file_sha1,
                File.source,
                Document.document_id,
                Document.content,
                Document.sha1,
                Document.chunk_index,
                Document.page_start,
                Document.page_end,
                Document.page_number,
                Document.token_count,
                Document.section_title,
                Document.doc_metadata,
                similarity.label("similarity")
            )
            .outerjoin(File, Document.file_id == File.id)  # File 정보 JOIN
        )

        # 3. 쿼리 실행 및 결과 처리
        # 상위 top_k개 조회
        results = self.session.execute(
            query.filter(Document.embedding.isnot(None))
            .order_by(similarity.desc())
            .limit(top_k)
        ).all()

        # 후처리
        filtered_results = [result for result in results if result.similarity >= similarity_threshold]

        # 결과가 없으면 상위 min_results개라도 반환
        if not filtered_results:
            filtered_results = results[:min_results] if results else []

        print(f"\n검색 결과: {len(filtered_results)}개 문서")
        print("=" * 100)

        return filtered_results

    def print_results(self, results: List[Any], max_content_length: int = 200):
        """
        검색 결과 출력 - 노트북의 출력 부분 분리

        Args:
            results: 검색 결과
            max_content_length: 출력할 내용 최대 길이
        """
        for idx, row in enumerate(results, 1):
            print(f"\n[{idx}] 유사도: {row.similarity:.4f}")
            print(f"파일: {row.source}")
            print(f"청크 인덱스: {row.chunk_index}")
            print(f"페이지: {row.page_number}")
            print(f"섹션: {row.section_title}")
            print(f"내용: {row.content[:max_content_length]}...")  # 처음 200자만 출력
            print("-" * 80)
