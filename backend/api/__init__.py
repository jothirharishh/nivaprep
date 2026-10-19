"""backend/api/__init__.py"""
from .questions import bp as questions_bp
from .textbook_qa import bp as textbook_qa_bp
from .admin_generation import bp as admin_generation_bp
from .live_generation import bp as live_generation_bp

__all__ = [
    "questions_bp",
    "textbook_qa_bp",
    "admin_generation_bp",
    "live_generation_bp",
]
