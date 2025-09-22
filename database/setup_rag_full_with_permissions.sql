-- =====================================================================
-- RAG DB Setup (Schema: rag)
-- Roles:
--   - Superuser: ai_admin  (이 계정으로 전체 스크립트 실행)
--   - App user:  app_user  (운영/애플리케이션 쿼리 실행)
-- =====================================================================

-- 0) 안전장치: 스키마 생성 및 소유자 지정
CREATE SCHEMA IF NOT EXISTS rag AUTHORIZATION ai_admin;

-- 1) 확장 (DB 단위) - public 스키마에 설치되는 것이 일반적
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;

-- 2) 원문 파일 테이블 (파일 단위 메타데이터)
DROP TABLE IF EXISTS rag.files CASCADE;
CREATE TABLE rag.files (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    file_path  text NOT NULL,
    file_sha1  char(40) NOT NULL,       -- 파일 전체 해시
    source     text,
    created_at timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp DEFAULT CURRENT_TIMESTAMP
);

-- 파일 중복 방지
CREATE UNIQUE INDEX IF NOT EXISTS uniq_files_sha1 ON rag.files(file_sha1);

-- 3) 청크 테이블 (문서/청크 단위)
DROP TABLE IF EXISTS rag.documents CASCADE;
CREATE TABLE rag.documents (
    id            bigserial PRIMARY KEY,
    file_id       uuid REFERENCES rag.files(id) ON DELETE CASCADE,  -- 파일 FK
    document_id   uuid DEFAULT gen_random_uuid(),                    -- 논리 문서 ID(청크 묶음)
    content       text NOT NULL,                                     -- 청크 내용
    sha1          char(40) NOT NULL,                                 -- 청크 내용 해시
    chunk_index   integer,                                           -- 문서 내 순번(0..N)
    section_title text,                                              -- 섹션/헤더명
    page_start    integer,
    page_end      integer,
    page_number   integer,
    token_count   integer,
    metadata      jsonb,
    embedding     vector(2000),                                      -- 벡터(차원 ≤2000)
    created_at    timestamp DEFAULT CURRENT_TIMESTAMP,
    updated_at    timestamp DEFAULT CURRENT_TIMESTAMP
);

-- 청크 중복 방지
CREATE UNIQUE INDEX IF NOT EXISTS uniq_documents_sha1 ON rag.documents(sha1);

-- 4) updated_at 자동 갱신 트리거 (rag 스키마에 생성)
CREATE OR REPLACE FUNCTION rag.set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_updated_at ON rag.documents;
CREATE TRIGGER trg_set_updated_at
BEFORE UPDATE ON rag.documents
FOR EACH ROW EXECUTE FUNCTION rag.set_updated_at();

-- 5) 일반 인덱스 (정렬/그룹/필터 최적화)
CREATE INDEX IF NOT EXISTS idx_documents_docid_chunk
  ON rag.documents (document_id, chunk_index);

CREATE INDEX IF NOT EXISTS idx_documents_docid_pages
  ON rag.documents (document_id, page_start, page_end);

CREATE INDEX IF NOT EXISTS idx_documents_page_number
  ON rag.documents (page_number);

-- JSONB 경로/키 탐색 최적화 (풀텍스트 아님)
CREATE INDEX IF NOT EXISTS idx_documents_metadata_gin
  ON rag.documents USING gin (metadata jsonb_path_ops);

-- 6) 키워드(스파스) 인덱스 - pg_trgm
CREATE INDEX IF NOT EXISTS idx_documents_content_trgm
  ON rag.documents USING gin (content gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_documents_metadata_trgm
  ON rag.documents USING gin ((metadata::text) gin_trgm_ops);

-- 7) 벡터(덴스) 인덱스 - HNSW (코사인)
--   ※ 매니지드 환경에서 HNSW 차원 제한(≤2000) 준수 필요
CREATE INDEX IF NOT EXISTS idx_documents_embedding_hnsw
  ON rag.documents USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

COMMENT ON TABLE rag.files IS '원본 문서(파일) 단위 메타데이터';
COMMENT ON COLUMN rag.files.id IS '파일 식별자 (UUID, PK)';
COMMENT ON COLUMN rag.files.file_path IS '파일 경로 또는 식별자';
COMMENT ON COLUMN rag.files.file_sha1 IS '파일 전체 해시값 (중복 방지)';
COMMENT ON COLUMN rag.files.source IS '파일 출처(예: 시스템, 업로드)';
COMMENT ON COLUMN rag.files.created_at IS '파일 등록일시 (자동)';

COMMENT ON TABLE rag.documents IS '문서를 청크 단위로 분할 저장';
COMMENT ON COLUMN rag.documents.id IS '청크 식별자 (PK)';
COMMENT ON COLUMN rag.documents.file_id IS '원본 파일 참조 (FK → files.id)';
COMMENT ON COLUMN rag.documents.document_id IS '논리적 문서 ID (예: 여러 파일 묶음)';
COMMENT ON COLUMN rag.documents.content IS '청크 텍스트 내용';
COMMENT ON COLUMN rag.documents.metadata IS '청크 메타데이터 (JSONB)';
COMMENT ON COLUMN rag.documents.chunk_index IS '문서 내 청크 순번 (0부터 시작)';
COMMENT ON COLUMN rag.documents.section_title IS '해당 청크의 섹션/헤더명';
COMMENT ON COLUMN rag.documents.page_start IS '시작 페이지 번호';
COMMENT ON COLUMN rag.documents.page_end IS '끝 페이지 번호';
COMMENT ON COLUMN rag.documents.token_count IS '청크 토큰 수 (검색/패킹 관리)';
COMMENT ON COLUMN rag.documents.sha1 IS '청크 내용 SHA1 해시 (중복 방지/추적)';
COMMENT ON COLUMN rag.documents.embedding IS '임베딩 벡터 (pgvector)';
COMMENT ON COLUMN rag.documents.created_at IS '생성일시 (자동)';
COMMENT ON COLUMN rag.documents.updated_at IS '갱신일시 (자동)';

-- 8) 권한/검색 경로 설정 (app_user가 rag 스키마 객체에 접근/작업 가능하도록)
--    ※ 아래 구문은 ai_admin(슈퍼계정)으로 실행

-- 스키마 사용 권한
GRANT USAGE ON SCHEMA rag TO app_user;

-- 테이블 권한 (기존 + 향후 추가 테이블까지 자동 부여)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA rag TO app_user;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA rag TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA rag
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA rag
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO app_user;

-- app_user 로그인 시 기본 검색 경로 및 HNSW 검색 폭 기본값(가능 시) 설정
-- 일부 매니지드 환경에서 확장 GUC(예: hnsw.ef_search)를 ROLE 기본값으로 지정이 제한될 수 있습니다.
ALTER ROLE app_user SET search_path = rag, public;

-- (옵션) DB 단위 기본값으로 설정 (매니지드 환경 권고)
-- 아래 줄에서 <YOUR_DB_NAME> 을 실제 DB명으로 교체 후 실행
ALTER DATABASE vectordb SET hnsw.ef_search = 80;

-- (대안) 애플리케이션 커넥션 옵션으로 세션별 지정
-- e.g., psycopg: options='-c hnsw.ef_search=80'


-- =====================================================
-- 권한 설정 (ai_admin 계정에서 실행)
-- =====================================================

-- rag 스키마 사용 및 객체 생성 권한 부여 (DROP 권한은 없음)
GRANT USAGE, CREATE ON SCHEMA rag TO app_user;

-- 기존 테이블에 대한 권한 부여
GRANT SELECT, INSERT, UPDATE, DELETE ON rag.files TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON rag.documents TO app_user;

-- 시퀀스 권한 부여 (자동 증가 PK용)
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA rag TO app_user;

-- 앞으로 rag 스키마에 새로 생성되는 테이블/시퀀스에도 기본 권한 자동 부여
ALTER DEFAULT PRIVILEGES FOR ROLE ai_admin IN SCHEMA rag
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES FOR ROLE ai_admin IN SCHEMA rag
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO app_user;

  -- ai_admin 계정에서 함수 생성
  CREATE OR REPLACE FUNCTION rag.reset_documents_id_seq(start_value BIGINT DEFAULT 1)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  AS $$
  BEGIN
      EXECUTE format('ALTER SEQUENCE rag.documents_id_seq RESTART WITH %s', start_value);
  END;
  $$;

  -- app_user에게 실행 권한 부여
  GRANT EXECUTE ON FUNCTION rag.reset_documents_id_seq TO app_user;