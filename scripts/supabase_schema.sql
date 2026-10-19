-- =============================================================================
-- BoardMate 10 — Supabase / PostgreSQL Schema with pgvector
-- Run this script in the Supabase SQL Editor (Dashboard -> SQL Editor -> New Query)
-- =============================================================================

-- 1. Enable pgvector extension for RAG semantic search
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Sources (Textbook metadata)
CREATE TABLE IF NOT EXISTS sources (
    source_id        TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    subject_id       TEXT NOT NULL,
    medium           TEXT NOT NULL DEFAULT 'English',
    board            TEXT NOT NULL DEFAULT 'Tamil Nadu State Board',
    curriculum       TEXT NOT NULL DEFAULT 'Samacheer Kalvi',
    class_level      INTEGER NOT NULL DEFAULT 10,
    edition          TEXT NOT NULL,
    publisher        TEXT NOT NULL DEFAULT '',
    source_uri       TEXT,
    rights_status    TEXT NOT NULL,
    rights_notes     TEXT NOT NULL DEFAULT '',
    file_sha256      TEXT,
    ingestion_status TEXT NOT NULL DEFAULT 'completed',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Chapters (56 Canonical Class 10 chapters across 5 subjects)
CREATE TABLE IF NOT EXISTS chapters (
    chapter_id      TEXT PRIMARY KEY,
    source_id       TEXT NOT NULL REFERENCES sources(source_id) ON DELETE CASCADE,
    subject_id      TEXT NOT NULL,
    chapter_number  INTEGER NOT NULL,
    title           TEXT NOT NULL,
    start_pdf_page  INTEGER NOT NULL DEFAULT 0,
    end_pdf_page    INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'reviewed'
);

CREATE INDEX IF NOT EXISTS idx_chapters_subject_id ON chapters(subject_id);

-- 4. Passages (8,398 extracted textbook chunks with 384-dim embeddings)
CREATE TABLE IF NOT EXISTS passages (
    passage_id          TEXT PRIMARY KEY,
    source_id           TEXT NOT NULL REFERENCES sources(source_id) ON DELETE CASCADE,
    subject_id          TEXT NOT NULL,
    chapter_id          TEXT NOT NULL REFERENCES chapters(chapter_id) ON DELETE CASCADE,
    chapter_title       TEXT NOT NULL,
    language            TEXT NOT NULL DEFAULT 'en',
    pdf_page_index      INTEGER NOT NULL,
    printed_page_label  TEXT NOT NULL DEFAULT '',
    section_heading     TEXT,
    text                TEXT NOT NULL,
    extraction_method   TEXT NOT NULL DEFAULT 'pymupdf',
    extraction_quality  TEXT NOT NULL DEFAULT 'reviewed',
    content_hash        TEXT NOT NULL DEFAULT '',
    embedding_model     TEXT DEFAULT 'all-MiniLM-L6-v2',
    index_version       TEXT DEFAULT 'v1',
    embedding           vector(384)
);

CREATE INDEX IF NOT EXISTS idx_passages_chapter_id ON passages(chapter_id);
CREATE INDEX IF NOT EXISTS idx_passages_subject_id ON passages(subject_id);

-- HNSW vector cosine similarity index for fast RAG retrieval
CREATE INDEX IF NOT EXISTS idx_passages_embedding_hnsw 
    ON passages USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- 5. Questions (Practice & Live AI-generated bank)
CREATE TABLE IF NOT EXISTS questions (
    question_id         TEXT PRIMARY KEY,
    subject_id          TEXT NOT NULL,
    source_id           TEXT NOT NULL,
    chapter_id          TEXT NOT NULL,
    chapter_title       TEXT NOT NULL,
    language            TEXT NOT NULL DEFAULT 'en',
    origin              TEXT NOT NULL DEFAULT 'ai_generated',
    question_type       TEXT NOT NULL DEFAULT 'mcq',
    question_text       TEXT NOT NULL,
    options_json        TEXT NOT NULL,
    correct_option_id   TEXT NOT NULL,
    explanation         TEXT NOT NULL DEFAULT '',
    source_refs_json    TEXT NOT NULL DEFAULT '[]',
    difficulty          TEXT NOT NULL DEFAULT 'medium',
    review_status       TEXT NOT NULL DEFAULT 'live',
    content_version     INTEGER NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    review_notes        TEXT,
    reviewed_by         TEXT,
    reviewed_at         TIMESTAMPTZ,
    model_provider      TEXT DEFAULT 'groq',
    model_id            TEXT,
    prompt_version      TEXT DEFAULT 'mcq-v1'
);

CREATE INDEX IF NOT EXISTS idx_questions_subject_chapter ON questions(subject_id, chapter_id);
CREATE INDEX IF NOT EXISTS idx_questions_review_status ON questions(review_status);

-- 6. Student Attempts (Optional server-side telemetry / sync)
CREATE TABLE IF NOT EXISTS student_attempts (
    attempt_id               TEXT PRIMARY KEY,
    local_student_id         TEXT NOT NULL,
    question_id              TEXT NOT NULL REFERENCES questions(question_id) ON DELETE CASCADE,
    subject_id               TEXT,
    chapter_id               TEXT,
    selected_option_id       TEXT,
    is_correct               INTEGER NOT NULL DEFAULT 0,
    mode                     TEXT NOT NULL DEFAULT 'practice',
    attempted_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    question_content_version INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_student_attempts_student_question ON student_attempts(local_student_id, question_id);
CREATE INDEX IF NOT EXISTS idx_student_attempts_sub_ch ON student_attempts(local_student_id, subject_id, chapter_id);

-- 7. Helper RAG Search Function (executes vector similarity query)
CREATE OR REPLACE FUNCTION match_passages(
    query_embedding vector(384),
    match_subject_id text,
    match_chapter_id text,
    match_count int DEFAULT 6
)
RETURNS TABLE (
    passage_id text,
    source_id text,
    subject_id text,
    chapter_id text,
    chapter_title text,
    pdf_page_index int,
    printed_page_label text,
    section_heading text,
    text text,
    similarity float
)
LANGUAGE sql STABLE
AS $$
    SELECT
        p.passage_id,
        p.source_id,
        p.subject_id,
        p.chapter_id,
        p.chapter_title,
        p.pdf_page_index,
        p.printed_page_label,
        p.section_heading,
        p.text,
        1 - (p.embedding <=> query_embedding) AS similarity
    FROM passages p
    WHERE p.subject_id = match_subject_id
      AND p.chapter_id = match_chapter_id
    ORDER BY p.embedding <=> query_embedding
    LIMIT match_count;
$$;
