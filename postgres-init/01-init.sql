-- n8n 전용 스키마 생성
CREATE SCHEMA IF NOT EXISTS n8n;

-- 뉴스 데이터는 public 스키마 사용 (기본값)

-- 1. 뉴스 원본 데이터 테이블
CREATE TABLE IF NOT EXISTS news_articles (
    id SERIAL PRIMARY KEY,
    url VARCHAR(1000) UNIQUE NOT NULL,
    title TEXT NOT NULL,
    content TEXT,
    summary TEXT,
    author VARCHAR(255),
    source VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    published_at TIMESTAMP,
    collected_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    thumbnail_url VARCHAR(1000),
    keywords TEXT[],
    tags TEXT[],
    
    status VARCHAR(50) DEFAULT 'active',
    
    CONSTRAINT unique_url UNIQUE(url)
);

-- 2. AI 분석 세션 테이블
CREATE TABLE IF NOT EXISTS analysis_sessions (
    id SERIAL PRIMARY KEY,
    session_name VARCHAR(255),
    analysis_type VARCHAR(100) NOT NULL,
    query_params JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100),
    
    date_from TIMESTAMP,
    date_to TIMESTAMP,
    sources TEXT[],
    categories TEXT[]
);

-- 3. AI 분석 결과 캐시 테이블
CREATE TABLE IF NOT EXISTS analysis_cache (
    id SERIAL PRIMARY KEY,
    session_id INTEGER REFERENCES analysis_sessions(id) ON DELETE CASCADE,
    article_id INTEGER REFERENCES news_articles(id) ON DELETE CASCADE,
    analysis_result JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    
    CONSTRAINT unique_session_article UNIQUE(session_id, article_id)
);

-- 4. 수집 로그 테이블
CREATE TABLE IF NOT EXISTS collection_logs (
    id SERIAL PRIMARY KEY,
    workflow_id VARCHAR(255),
    execution_id VARCHAR(255),
    source VARCHAR(255) NOT NULL,
    articles_collected INTEGER DEFAULT 0,
    articles_new INTEGER DEFAULT 0,
    articles_updated INTEGER DEFAULT 0,
    articles_failed INTEGER DEFAULT 0,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    status VARCHAR(50),
    error_message TEXT,
    metadata JSONB
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_news_published_at ON news_articles(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_collected_at ON news_articles(collected_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_source ON news_articles(source);
CREATE INDEX IF NOT EXISTS idx_news_category ON news_articles(category);
CREATE INDEX IF NOT EXISTS idx_news_status ON news_articles(status);
CREATE INDEX IF NOT EXISTS idx_news_keywords ON news_articles USING GIN(keywords);
CREATE INDEX IF NOT EXISTS idx_news_tags ON news_articles USING GIN(tags);

CREATE INDEX IF NOT EXISTS idx_analysis_created_at ON analysis_sessions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_analysis_type ON analysis_sessions(analysis_type);

CREATE INDEX IF NOT EXISTS idx_cache_expires_at ON analysis_cache(expires_at);
CREATE INDEX IF NOT EXISTS idx_cache_session ON analysis_cache(session_id);

CREATE INDEX IF NOT EXISTS idx_logs_started_at ON collection_logs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_source ON collection_logs(source);
CREATE INDEX IF NOT EXISTS idx_logs_status ON collection_logs(status);

-- 트리거 함수
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 트리거
DROP TRIGGER IF EXISTS update_news_articles_updated_at ON news_articles;
CREATE TRIGGER update_news_articles_updated_at 
    BEFORE UPDATE ON news_articles 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- 뷰: 최근 뉴스
CREATE OR REPLACE VIEW recent_news AS
SELECT 
    id,
    title,
    source,
    category,
    published_at,
    collected_at,
    url,
    summary,
    keywords
FROM news_articles
WHERE status = 'active'
ORDER BY published_at DESC;

-- 뷰: 수집 통계
CREATE OR REPLACE VIEW collection_stats AS
SELECT 
    source,
    DATE(started_at) as collection_date,
    COUNT(*) as total_runs,
    SUM(articles_collected) as total_collected,
    SUM(articles_new) as total_new,
    AVG(articles_collected) as avg_per_run,
    COUNT(CASE WHEN status = 'success' THEN 1 END) as successful_runs
FROM collection_logs
GROUP BY source, DATE(started_at)
ORDER BY collection_date DESC, source;