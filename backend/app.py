"""
backend/app.py
Flask application factory.
"""
from __future__ import annotations

import logging
import os

from flask import Flask, jsonify
from dotenv import load_dotenv

# Load .env before anything else (only for local development)
load_dotenv()

from .api import questions_bp, textbook_qa_bp, admin_generation_bp, live_generation_bp
from .repositories.db import init_db


def create_app() -> Flask:
    app = Flask(__name__)

    # ── CORS for Web client support ───────────────────────────────────────────
    try:
        from flask_cors import CORS
        CORS(app, resources={r"/*": {"origins": "*"}})
    except ImportError:
        pass

    # ── Logging ───────────────────────────────────────────────────────────────
    logging.basicConfig(
        level=logging.DEBUG if os.environ.get("FLASK_DEBUG") == "1" else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    # ── Config ────────────────────────────────────────────────────────────────
    from .config import get_config
    cfg = get_config()
    app.secret_key = cfg.flask_secret_key

    # ── Database ──────────────────────────────────────────────────────────────
    from .repositories.db import set_database_path
    set_database_path(cfg.database_path)
    init_db()

    # ── Blueprints (/v1 canonical and /api alias) ──────────────────────────────
    app.register_blueprint(questions_bp)
    app.register_blueprint(questions_bp, url_prefix="/api", name="questions_api")
    app.register_blueprint(textbook_qa_bp)
    app.register_blueprint(textbook_qa_bp, url_prefix="/api", name="textbook_qa_api")
    app.register_blueprint(admin_generation_bp)
    app.register_blueprint(admin_generation_bp, url_prefix="/api", name="admin_generation_api")
    app.register_blueprint(live_generation_bp)
    app.register_blueprint(live_generation_bp, url_prefix="/api", name="live_generation_api")

    # ── Health endpoint ───────────────────────────────────────────────────────
    @app.get("/health")
    def health():
        return jsonify({"status": "ok", "service": "boardmate10-api"})

    # ── Error handlers ────────────────────────────────────────────────────────
    @app.errorhandler(404)
    def not_found(e):
        return jsonify({"error": "Not found"}), 404

    @app.errorhandler(405)
    def method_not_allowed(e):
        return jsonify({"error": "Method not allowed"}), 405

    @app.errorhandler(413)
    def request_too_large(e):
        return jsonify({"error": "Request body too large"}), 413

    @app.errorhandler(500)
    def internal_error(e):
        logging.getLogger(__name__).exception("Internal server error")
        return jsonify({"error": "Internal server error"}), 500

    # ── Request size limit ────────────────────────────────────────────────────
    app.config["MAX_CONTENT_LENGTH"] = 64 * 1024  # 64 KB

    # ── Background Warmup ─────────────────────────────────────────────────────
    # Pre-warm embedding model in daemon thread so first generation request is fast
    import threading

    def _warmup_worker():
        try:
            from .rag.embeddings import get_embedder
            get_embedder()
        except Exception as exc:
            logging.getLogger(__name__).debug("Warmup error (non-fatal): %s", exc)

    threading.Thread(target=_warmup_worker, daemon=True).start()

    return app
