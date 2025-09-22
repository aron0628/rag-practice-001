-- =====================================================================
-- RAG DB Setup (Schema: rag) - 4000D halfvec 분리 테이블
-- Roles:
--   - Superuser: ai_admin   (전체 스크립트 실행)
--   - App user:  app_user   (운영/애플리케이션 쿼리 실행)
-- =====================================================================

-- 0) 안전장치: 스키마/확장
CREATE SCHEMA IF NOT EXISTS rag AUTHORIZATION ai_admin;

CREATE EXTENSION IF NOT EXISTS vector;
-- (선택) 기타 필요 시: CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================================
-- 1) 원문 파일 테이블 (4000D 전용)
-- =====================================================================
DROP TABLE IF EXISTS rag.files_4000 CASCADE;

CREATE TABLE rag.files_4000 (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_path  text NOT NULL,
    file_sha1  char(40) NOT NULL,        -- 파일 전체 해시
    source     text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE rag.files_4000 IS '4000D halfvec 파이프라인 전용 파일 메타';
COMMENT ON COLUMN rag.files_4000.file_sha1 IS '파일 전체 해시(SHA1)';

-- 중복 파일 방지 목적의 보조 인덱스(옵션)
CREATE UNIQUE INDEX IF NOT EXISTS files_4000_sha1_uidx
ON rag.files_4000 (file_sha1);

-- =====================================================================
-- 2) 문서(청크) 테이블 (4000D halfvec)
-- =====================================================================
DROP TABLE IF EXISTS rag.documents_4000 CASCADE;

CREATE TABLE rag.documents_4000 (
    id            bigserial PRIMARY KEY,
    file_id       uuid REFERENCES rag.files_4000(id) ON DELETE CASCADE, -- 파일 FK
    document_id   uuid DEFAULT gen_random_uuid(),                        -- 논리 문서 ID(청크 묶음)
    content       text NOT NULL,                                         -- 청크 내용
    sha1          char(40) NOT NULL,                                     -- 청크 내용 해시
    chunk_index   integer,                                               -- 문서 내 순번(0..N)
    section_title text,                                                  -- 섹션/헤더명
    page_start    integer,
    page_end      integer,
    page_number   integer,
    token_count   integer,
    metadata      jsonb,
    embedding_hv  halfvec(4000),                                         -- ★ 4000D half-precision 벡터
    created_at    timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at    timestamp DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE rag.documents_4000 IS '4000D halfvec 파이프라인 전용 문서 청크';
COMMENT ON COLUMN rag.documents_4000.embedding_hv IS '임베딩(halfvec, 4000차원)';

-- (옵션) 동일 청크 재처리 방지
CREATE UNIQUE INDEX IF NOT EXISTS documents_4000_sha1_uidx
ON rag.documents_4000 (sha1);

-- =====================================================================
-- 3) 벡터 인덱스 (정확도 우선: HNSW + cosine)
-- =====================================================================

-- 인덱스 생성은 데이터가 어느 정도 적재된 후가 유리하며,
-- ONLINE 생성 위해 CONCURRENTLY 사용 권장.
CREATE INDEX CONCURRENTLY IF NOT EXISTS documents_4000_emb_hnsw_cosine
ON rag.documents_4000
USING hnsw (embedding_hv halfvec_cosine_ops)
WITH (m = 16, ef_construction = 64);

-- (선택) IVFFlat 인덱스가 필요할 경우 예시
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS documents_4000_emb_ivf_cosine
-- ON rag.documents_4000
-- USING ivfflat (embedding_hv halfvec_cosine_ops)
-- WITH (lists = 1000);

-- =====================================================================
-- 4) 변환/적재 보조 함수 (4096 → 4000 절단 + halfvec 캐스팅)
-- =====================================================================

-- 4096 float32 배열을 1..4000까지만 사용하여 halfvec(4000)으로 변환
-- ※ 호출 전 배열 길이(4096) 검증은 애플리케이션 측에서 수행 권장
CREATE OR REPLACE FUNCTION rag.to_halfvec_4000(v float4[])
RETURNS halfvec(4000)
LANGUAGE sql
AS $$
  SELECT (v[1:4000])::halfvec(4000)
$$;

COMMENT ON FUNCTION rag.to_halfvec_4000(float4[]) IS
'4096D float32 배열을 앞 4000D로 절단 후 halfvec(4000) 캐스팅';

-- =====================================================================
-- 5) 권한 부여(운영 계정)
-- =====================================================================

-- 스키마 접근
GRANT USAGE ON SCHEMA rag TO app_user;

-- 테이블 권한
GRANT SELECT, INSERT, UPDATE, DELETE ON rag.files_4000     TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON rag.documents_4000 TO app_user;

-- 생성된 시퀀스 권한(bigserial 등)
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA rag TO app_user;

-- 함수 실행 권한
GRANT EXECUTE ON FUNCTION rag.to_halfvec_4000(float4[]) TO app_user;

-- (선택) 향후 생성될 객체에 대한 기본 권한
-- ALTER DEFAULT PRIVILEGES IN SCHEMA rag
--   GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA rag
--   GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO app_user;

-- =====================================================================
-- 6) 조회 가이드 (예시)
-- =====================================================================
-- 정확도(Recall) 우선 시, ef_search 상향(트랜잭션 단위로 SET LOCAL 권장)
-- SET LOCAL hnsw.ef_search = 100;

-- k-NN 검색 (cosine)
-- SELECT id, file_id, document_id, page_number
-- FROM rag.documents_4000
-- ORDER BY embedding_hv <=> rag.to_halfvec_4000($1::float4[])  -- $1: 4096D float32 배열
-- LIMIT 10;

-- 주의: ORDER BY에 거리 연산자(<=>, cosine)를 직접 사용해야 인덱스가 활용됩니다.
--       거리에 대한 2차 가공(예: 1 - (embedding_hv <=> ...))을 넣으면 플래너가 인덱스를 피할 수 있음.