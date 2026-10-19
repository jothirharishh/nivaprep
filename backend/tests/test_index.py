"""
backend/tests/test_index.py
Tests for FAISS index persistence in backend/ingestion/index.py.
"""
import pytest
from unittest.mock import patch, MagicMock
from backend.ingestion.index import build_index
from backend.ingestion.chunk import Chunk


def test_build_index_empty_chunks_raises():
    with pytest.raises(ValueError, match="Cannot build index from empty chunk list"):
        build_index([])


@patch("backend.ingestion.index.embed_texts")
@patch("backend.ingestion.index.FAISSRetriever")
def test_build_index_persists_chunks(mock_retriever_cls, mock_embed):
    mock_retriever = MagicMock()
    mock_retriever_cls.return_value = mock_retriever
    mock_embed.return_value = [[0.1, 0.2, 0.3]]

    chunk = Chunk(
        passage_id="p01",
        source_id="src01",
        subject_id="science",
        chapter_id="ch01",
        chapter_title="Laws of Motion",
        language="en",
        pdf_page_index=0,
        printed_page_label="1",
        section_heading="Intro",
        text="Newton's laws are fundamental.",
        content_hash="abc",
        extraction_method="pymupdf",
        extraction_quality="reviewed",
    )

    build_index([chunk], index_version="test_v1")
    assert mock_embed.called
    assert mock_retriever.save_index.called
