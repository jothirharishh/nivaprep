# BoardMate 10 — Cloud Hosting & Supabase Deployment Guide

This guide walks you through deploying the **BoardMate 10** backend to **Render** and migrating data to a managed **Supabase PostgreSQL** cloud database with the `pgvector` semantic search extension.

---

## Architecture Overview

```text
┌──────────────────────────────────────┐
│  BoardMate 10 Flutter Android App    │
│  (Offline-capable, SQLite cache)     │
└──────────────────┬───────────────────┘
                   │ HTTPS API Requests
                   ▼
┌──────────────────────────────────────┐
│  Render Web Service (Singapore / AP) │
│  - Python 3.12 + Flask + Gunicorn    │
│  - Groq API Integration (LLM)        │
│  - Sentence-Transformers Embeddings  │
└──────────────────┬───────────────────┘
                   │
                   ▼ PostgreSQL connection with pgvector
┌──────────────────────────────────────┐
│  Supabase Cloud Database             │
│  - 5 Sources & 56 Chapters           │
│  - 8,398 Passages + Vector(384)      │
│  - Questions & Practice Bank         │
│  - HNSW Cosine Similarity Index      │
└──────────────────────────────────────┘
```

---

## Step 1: Set Up Supabase Cloud Database

1. Sign up or log in at [supabase.com](https://supabase.com).
2. Click **New Project**:
   - **Name:** `boardmate10`
   - **Database Password:** Choose a strong password and save it securely.
   - **Region:** Select **South Asia (Mumbai)** (`ap-south-1`) or **Southeast Asia (Singapore)** (`ap-southeast-1`) for lowest latency in Tamil Nadu.
   - **Plan:** Free tier ($0).
3. Open the **SQL Editor** from the left navigation bar.
4. Click **New Query**, copy the entire contents of [`scripts/supabase_schema.sql`](scripts/supabase_schema.sql), paste it into the editor, and click **Run**.
   - *This creates the `vector` extension, `sources`, `chapters`, `passages` (with `embedding vector(384)`), `questions`, `student_attempts` tables, HNSW indexes, and helper search functions.*
5. Retrieve your connection string:
   - Go to **Project Settings** (gear icon) -> **Database**.
   - Under **Connection string**, select **URI**.
   - Choose **Mode: Session** (port `5432`) or **Mode: Transaction** (port `6543`).
   - Copy the string. It will look like:
     ```text
     postgresql://postgres.[PROJECT-REF]:[YOUR-PASSWORD]@aws-0-ap-south-1.pooler.supabase.com:6543/postgres
     ```

---

## Step 2: Migrate Textbook Data to Supabase

Run the migration script to transfer all 5 sources, 56 chapters, 8,398 textbook passages (with their 384-dimensional vector embeddings), and questions into Supabase:

```powershell
# Set your Supabase connection string
$env:DATABASE_URL="postgresql://postgres.[PROJECT-REF]:[YOUR-PASSWORD]@aws-0-ap-south-1.pooler.supabase.com:6543/postgres"

# Execute migration script
python scripts/migrate_sqlite_to_supabase.py
```

*Expected output:*
```text
Opening local SQLite database: backend/data/boardmate.db
Connecting to Supabase PostgreSQL...
Connected successfully!
Migrating sources...
  ✓ 5 sources migrated.
Migrating chapters...
  ✓ 56 chapters migrated.
Migrating passages with vector embeddings...
  ... 8398/8398 passages uploaded (100%)
  ✓ All 8398 passages migrated successfully.
Migrating questions...
  ✓ questions migrated.

🎉 Migration completed successfully! Supabase database is ready.
```

---

## Step 3: Deploy Backend on Render

### Option A: Using the Render Blueprint (`render.yaml`) *(Fastest)*

1. Push your repository to **GitHub**.
2. Log in to [render.com](https://render.com) and go to the **Dashboard**.
3. Click **New +** -> **Blueprint**.
4. Connect your GitHub repository.
5. Render will automatically detect [`render.yaml`](render.yaml).
6. Under Environment Variables, input your secret values:
   - `DATABASE_URL`: Your Supabase connection URI from Step 1.
   - `GROQ_API_KEY`: Your Groq API key (`gsk_...`).
7. Click **Apply**. Render will install dependencies and start the service.

### Option B: Manual Web Service Creation

1. In Render Dashboard, click **New +** -> **Web Service**.
2. Connect your Git repository.
3. Configure the service:
   - **Name:** `boardmate10-api`
   - **Region:** `Singapore (Southeast Asia)`
   - **Branch:** `main`
   - **Runtime:** `Python 3`
   - **Build Command:** `pip install -r backend/requirements.txt`
   - **Start Command:** `gunicorn --bind 0.0.0.0:$PORT --workers 2 --threads 4 --timeout 120 "backend.app:create_app()"`
   - **Plan:** `Free` or `Starter` ($7/mo for 24/7 uptime without sleep)
4. Add the following **Environment Variables**:
   | Variable | Value | Notes |
   |---|---|---|
   | `DATABASE_URL` | `postgresql://postgres...` | Your Supabase connection string |
   | `GROQ_API_KEY` | `gsk_...` | Your Groq API key |
   | `GROQ_MODEL` | `llama-3.3-70b-versatile` | Supported Groq model |
   | `FLASK_ENV` | `production` | Production mode |
   | `FLASK_SECRET_KEY` | `[Random String]` | e.g. run `openssl rand -hex 16` |
   | `ADMIN_API_KEY` | `[Random Secret]` | Key to protect admin curation routes |
   | `PYTHON_VERSION` | `3.12.6` | Python version |
5. Click **Create Web Service**.

Once deployed, Render gives you a secure live URL:
```text
https://boardmate10-api.onrender.com
```

Verify deployment by visiting:
```text
https://boardmate10-api.onrender.com/health
```
*(Should return `{"status": "ok"}`)*

---

## Step 4: Connect the Flutter Android App to Production

By default, the Flutter app targets your local environment during development. To target your live Render API:

### For Debug / Testing:
```bash
flutter run --dart-define=API_URL=https://boardmate10-api.onrender.com
```

### For Production Release APK:
```bash
flutter build apk --release --dart-define=API_URL=https://boardmate10-api.onrender.com
```

---

## Tips & Troubleshooting

1. **Supabase Connection Pooling:**
   - If using the **Transaction Pooler** (port `6543`), disable prepared statements or use standard SQL parameters (which our wrapper handles automatically).
   - If using port `5432`, ensure your Supabase network allows external connections (enabled by default on Supabase).
2. **Render Free Tier Inactivity:**
   - On Render's Free tier, services spin down after 15 minutes of inactivity and take ~30–45s to wake up on the first hit.
   - For a production student experience during exam season, the $7/month Starter plan keeps the service warm 24/7 with zero spin-down.
3. **Local Development Fallback:**
   - If `DATABASE_URL` is omitted, the backend automatically defaults to local SQLite (`backend/data/boardmate.db`) and local FAISS files without any code changes.
