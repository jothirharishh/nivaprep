"""
backend/models/source.py
Source / textbook registry data model.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional


class RightsStatus(str, Enum):
    PERMISSION_CONFIRMED = "permission_confirmed"
    PUBLIC_TERMS_REVIEWED = "public_terms_reviewed"
    USER_SUPPLIED_REVIEW_REQUIRED = "user_supplied_review_required"
    RESTRICTED = "restricted"
    UNKNOWN = "unknown"


class IngestionStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class Source:
    source_id: str
    title: str
    subject_id: str
    edition: str
    rights_status: RightsStatus
    medium: str = "English"
    board: str = "Tamil Nadu State Board"
    curriculum: str = "Samacheer Kalvi"
    class_level: int = 10
    publisher: str = "State Council of Educational Research and Training"
    rights_notes: str = ""
    ingestion_status: IngestionStatus = IngestionStatus.PENDING
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    source_uri: Optional[str] = None
    file_sha256: Optional[str] = None

    def validate(self) -> list[str]:
        errors: list[str] = []
        if not self.source_id:
            errors.append("source_id must not be empty")
        if not self.title:
            errors.append("title must not be empty")
        if not self.subject_id:
            errors.append("subject_id must not be empty")
        if self.class_level != 10:
            errors.append("class_level must be 10 for BoardMate 10")
        return errors

    def to_dict(self) -> dict:
        return {
            "source_id": self.source_id,
            "title": self.title,
            "subject_id": self.subject_id,
            "medium": self.medium,
            "board": self.board,
            "curriculum": self.curriculum,
            "class_level": self.class_level,
            "edition": self.edition,
            "publisher": self.publisher,
            "source_uri": self.source_uri,
            "rights_status": self.rights_status.value,
            "rights_notes": self.rights_notes,
            "file_sha256": self.file_sha256,
            "ingestion_status": self.ingestion_status.value,
            "created_at": self.created_at.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Source":
        return cls(
            source_id=data["source_id"],
            title=data["title"],
            subject_id=data["subject_id"],
            medium=data.get("medium", "English"),
            board=data.get("board", "Tamil Nadu State Board"),
            curriculum=data.get("curriculum", "Samacheer Kalvi"),
            class_level=int(data.get("class_level", 10)),
            edition=data["edition"],
            publisher=data.get("publisher", ""),
            rights_status=RightsStatus(data.get("rights_status", RightsStatus.UNKNOWN.value)),
            rights_notes=data.get("rights_notes", ""),
            ingestion_status=IngestionStatus(
                data.get("ingestion_status", IngestionStatus.PENDING.value)
            ),
            created_at=datetime.fromisoformat(data["created_at"])
            if "created_at" in data
            else datetime.now(timezone.utc),
            source_uri=data.get("source_uri"),
            file_sha256=data.get("file_sha256"),
        )
