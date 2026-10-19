"""
scripts/migrate_sqlite_to_supabase.py
Transfers all sources, chapters, passages (with embeddings), and questions
from local SQLite (backend/data/boardmate.db) to Supabase / PostgreSQL.

Usage:
    python scripts/migrate_sqlite_to_supabase.py --db-url "postgresql://postgres:PASSWORD@HOST:5432/postgres"

Or via environment variable:
    export DATABASE_URL="postgresql://postgres:PASSWORD@HOST:5432/postgres"
    python scripts/migrate_sqlite_to_supabase.py
"""
import argparse
import os
import sqlite3
import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.rag.embeddings import embed_texts


def get_sqlite_conn(sqlite_path: str = "backend/data/boardmate.db") -> sqlite3.Connection:
    if not os.path.exists(sqlite_path):
        raise FileNotFoundError(f"SQLite database not found at {sqlite_path}")
    conn = sqlite3.connect(sqlite_path)
    conn.row_factory = sqlite3.Row
    return conn


def get_pg_conn(db_url: str):
    try:
        import psycopg2
        from psycopg2.extras import execute_batch
    except ImportError:
        print("Error: psycopg2 is required. Run: pip install psycopg2-binary")
        sys.exit(1)

    from backend.config import sanitize_database_url
    db_url = sanitize_database_url(db_url)

    try:
        conn = psycopg2.connect(db_url)
        return conn
    except psycopg2.OperationalError as e:
        err_msg = str(e)
        if "could not translate host name" in err_msg and "supabase.co" in db_url:
            print("Direct Supabase hostname requires IPv6, which is not available on this network.")
            print("Attempting automatic failover to Supabase IPv4 Connection Pooler...")
            import re
            m = re.match(r"^postgresql://([^:]+):([^@]+)@db\.([^.]+)\.supabase\.co(?::\d+)?/(.+)$", db_url)
            if m:
                user, pw, proj, dbname = m.groups()
                regions = ["ap-south-1", "ap-southeast-1", "us-east-1", "eu-central-1"]
                for region in regions:
                    pooler_host = f"aws-0-{region}.pooler.supabase.com"
                    pooler_url = f"postgresql://postgres.{proj}:{pw}@{pooler_host}:6543/{dbname}"
                    try:
                        conn = psycopg2.connect(pooler_url, connect_timeout=6)
                        print(f"  [OK] Connected via IPv4 pooler: {pooler_host}:6543", flush=True)
                        return conn
                    except Exception:
                        continue
        raise


def migrate_sources(sqlite_conn, pg_conn):
    print("Migrating sources...")
    rows = sqlite_conn.execute("SELECT * FROM sources").fetchall()
    with pg_conn.cursor() as cur:
        for r in rows:
            cur.execute("""
                INSERT INTO sources (
                    source_id, title, subject_id, medium, board, curriculum,
                    class_level, edition, publisher, source_uri, rights_status,
                    rights_notes, file_sha256, ingestion_status, created_at
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (source_id) DO UPDATE SET
                    title = EXCLUDED.title,
                    ingestion_status = EXCLUDED.ingestion_status;
            """, (
                r["source_id"], r["title"], r["subject_id"], r["medium"], r["board"],
                r["curriculum"], r["class_level"], r["edition"], r["publisher"],
                r["source_uri"], r["rights_status"], r["rights_notes"],
                r["file_sha256"], r["ingestion_status"], r["created_at"]
            ))
    pg_conn.commit()
    print(f"  [OK] {len(rows)} sources migrated.")


def migrate_chapters(sqlite_conn, pg_conn):
    print("Migrating chapters...")
    rows = sqlite_conn.execute("SELECT * FROM chapters").fetchall()
    with pg_conn.cursor() as cur:
        for r in rows:
            cur.execute("""
                INSERT INTO chapters (
                    chapter_id, source_id, subject_id, chapter_number,
                    title, start_pdf_page, end_pdf_page, status
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (chapter_id) DO UPDATE SET
                    title = EXCLUDED.title,
                    status = EXCLUDED.status;
            """, (
                r["chapter_id"], r["source_id"], r["subject_id"], r["chapter_number"],
                r["title"], r["start_pdf_page"], r["end_pdf_page"], r["status"]
            ))
    pg_conn.commit()
    print(f"  [OK] {len(rows)} chapters migrated.")


def migrate_passages(sqlite_conn, pg_conn, batch_size=200):
    import json
    from pathlib import Path
    from psycopg2.extras import execute_batch

    print("Migrating passages with vector embeddings (this may take a few moments)...", flush=True)
    total_count = sqlite_conn.execute("SELECT count(*) FROM passages").fetchone()[0]
    print(f"Total passages to migrate: {total_count}", flush=True)

    # Pre-load known embeddings from FAISS cache if available
    vector_cache: dict[str, list[float]] = {}
    faiss_file = Path("backend/rag/indexes/v1/passages.faiss")
    meta_file = Path("backend/rag/indexes/v1/passages_metadata.json")
    if faiss_file.exists() and meta_file.exists():
        try:
            import faiss
            index = faiss.read_index(str(faiss_file))
            with open(meta_file, "r", encoding="utf-8") as f:
                meta_list = json.load(f)
            if index.ntotal == len(meta_list):
                print(f"  Loaded {index.ntotal} precomputed embeddings from local FAISS cache.", flush=True)
                for i, m in enumerate(meta_list):
                    vector_cache[m["passage_id"]] = index.reconstruct(i).tolist()
        except Exception as e:
            print(f"  (Note: could not preload FAISS cache: {e}; will compute embeddings on the fly)", flush=True)

    offset = 0
    migrated = 0

    while offset < total_count:
        rows = sqlite_conn.execute(
            f"SELECT * FROM passages ORDER BY passage_id LIMIT {batch_size} OFFSET {offset}"
        ).fetchall()
        if not rows:
            break

        # Check which vectors are cached vs missing
        missing_texts = []
        missing_indices = []
        batch_embeddings = []
        for i, r in enumerate(rows):
            pid = r["passage_id"]
            if pid in vector_cache:
                batch_embeddings.append(vector_cache[pid])
            else:
                batch_embeddings.append(None)
                missing_texts.append(r["text"])
                missing_indices.append(i)

        if missing_texts:
            computed = embed_texts(missing_texts)
            for idx, emb in zip(missing_indices, computed):
                emb_list = emb.tolist() if hasattr(emb, "tolist") else list(emb)
                batch_embeddings[idx] = emb_list
                vector_cache[rows[idx]["passage_id"]] = emb_list

        records = []
        for r, emb in zip(rows, batch_embeddings):
            emb_str = "[" + ",".join(f"{x:.6f}" for x in emb) + "]"
            records.append((
                r["passage_id"], r["source_id"], r["subject_id"], r["chapter_id"],
                r["chapter_title"], r["language"], r["pdf_page_index"],
                r["printed_page_label"], r["section_heading"], r["text"],
                r["extraction_method"], r["extraction_quality"], r["content_hash"],
                r["embedding_model"], r["index_version"], emb_str
            ))

        with pg_conn.cursor() as cur:
            execute_batch(cur, """
                INSERT INTO passages (
                    passage_id, source_id, subject_id, chapter_id, chapter_title,
                    language, pdf_page_index, printed_page_label, section_heading,
                    text, extraction_method, extraction_quality, content_hash,
                    embedding_model, index_version, embedding
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::vector)
                ON CONFLICT (passage_id) DO UPDATE SET
                    text = EXCLUDED.text,
                    embedding = EXCLUDED.embedding;
            """, records)
        pg_conn.commit()

        migrated += len(records)
        offset += batch_size
        print(f"  ... {migrated}/{total_count} passages uploaded ({migrated*100//total_count}%)", flush=True)

    print(f"  [OK] All {migrated} passages migrated successfully.", flush=True)


def migrate_questions(sqlite_conn, pg_conn):
    print("Migrating questions...")
    rows = sqlite_conn.execute("SELECT * FROM questions").fetchall()
    if not rows:
        print("  (No questions to migrate)")
        return

    with pg_conn.cursor() as cur:
        for r in rows:
            cur.execute("""
                INSERT INTO questions (
                    question_id, subject_id, source_id, chapter_id, chapter_title,
                    language, origin, question_type, question_text, options_json,
                    correct_option_id, explanation, source_refs_json, difficulty,
                    review_status, content_version, created_at, updated_at,
                    review_notes, reviewed_by, reviewed_at, model_provider,
                    model_id, prompt_version
                ) VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (question_id) DO UPDATE SET
                    question_text = EXCLUDED.question_text,
                    review_status = EXCLUDED.review_status;
            """, (
                r["question_id"], r["subject_id"], r["source_id"], r["chapter_id"],
                r["chapter_title"], r["language"], r["origin"], r["question_type"],
                r["question_text"], r["options_json"], r["correct_option_id"],
                r["explanation"], r["source_refs_json"], r["difficulty"],
                r["review_status"], r["content_version"], r["created_at"],
                r["updated_at"], r["review_notes"], r["reviewed_by"],
                r["reviewed_at"], r["model_provider"], r["model_id"],
                r["prompt_version"]
            ))
    pg_conn.commit()
    print(f"  [OK] {len(rows)} questions migrated.")


def main():
    parser = argparse.ArgumentParser(description="Migrate SQLite data to Supabase PostgreSQL")
    parser.add_argument("--db-url", help="PostgreSQL connection string (or set DATABASE_URL env var)")
    parser.add_argument("--sqlite-path", default="backend/data/boardmate.db", help="Path to SQLite db")
    parser.add_argument("--skip-passages", action="store_true", help="Skip passages embedding upload")
    args = parser.parse_args()

    db_url = args.db_url or os.environ.get("DATABASE_URL")
    if not db_url:
        print("Error: DATABASE_URL must be provided via --db-url or environment variable.")
        print('Example: python scripts/migrate_sqlite_to_supabase.py --db-url "postgresql://postgres:pass@host:5432/postgres"')
        sys.exit(1)

    print(f"Opening local SQLite database: {args.sqlite_path}")
    sqlite_conn = get_sqlite_conn(args.sqlite_path)

    print("Connecting to Supabase PostgreSQL...")
    pg_conn = get_pg_conn(db_url)
    print("Connected successfully!")

    try:
        migrate_sources(sqlite_conn, pg_conn)
        migrate_chapters(sqlite_conn, pg_conn)
        if not args.skip_passages:
            migrate_passages(sqlite_conn, pg_conn)
        migrate_questions(sqlite_conn, pg_conn)
        print("\n[SUCCESS] Migration completed successfully! Supabase database is ready.")
    finally:
        sqlite_conn.close()
        pg_conn.close()


if __name__ == "__main__":
    main()
