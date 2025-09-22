"""Sparse Retriever 구현 - pg_trgm 기반 텍스트 유사도 검색"""

from typing import List, Any

from sqlalchemy import select, func
from sqlalchemy.orm import Session

from ..models import Document, File


class SparseRetriever:
    """pg_trgm 기반 텍스트 유사도 검색기"""

    def __init__(self, session: Session):
        """
        Args:
            session: SQLAlchemy 세션
        """
        self.session = session

    def search(
            self,
            question: str,
            top_k: int = 20,
            similarity_threshold: float = 0.3,
            min_results: int = 5
    ) -> List[Any]:
        """
        텍스트 유사도 기반 문서 검색 - pg_trgm similarity 함수 사용

        Args:
            question: 검색할 질문
            top_k: 조회할 최대 문서 수
            similarity_threshold: 유사도 임계값 (0.0 ~ 1.0)
            min_results: 최소 반환 문서 수

        Returns:
            검색 결과 리스트
        """
        # 1. pg_trgm similarity 함수를 ORM으로 정의
        similarity = func.similarity(Document.content, question)

        # 2. 텍스트 유사도 검색 쿼리 생성
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
        # similarity_threshold를 WHERE 절에 적용하고 상위 top_k개 조회
        results = self.session.execute(
            query.where(similarity > similarity_threshold)
            .order_by(similarity.desc())
            .limit(top_k)
        ).all()

        # 4. 결과가 min_results보다 적으면 threshold 무시하고 상위 결과 반환
        if len(results) < min_results:
            # threshold 조건 없이 다시 조회
            results = self.session.execute(
                query.order_by(similarity.desc())
                .limit(min_results)
            ).all()

        print(f"\n검색 결과: {len(results)}개 문서")
        print("=" * 100)

        return results

    def print_results(self, results: List[Any], max_content_length: int = 200):
        """
        검색 결과 출력 - dense_retriever와 동일한 형식

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