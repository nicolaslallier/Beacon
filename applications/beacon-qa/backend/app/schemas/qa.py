"""Pydantic schemas for QA domain."""

from datetime import datetime
from typing import Any, List, Optional

from pydantic import BaseModel, Field


class TestCaseBase(BaseModel):
    name: str = Field(..., max_length=200)
    prompt: str
    expected_response: Optional[str] = None
    rubric: Optional[dict[str, Any]] = None


class TestCaseCreate(TestCaseBase):
    pass


class TestCaseUpdate(BaseModel):
    name: Optional[str] = Field(default=None, max_length=200)
    prompt: Optional[str] = None
    expected_response: Optional[str] = None
    rubric: Optional[dict[str, Any]] = None


class TestCaseOut(TestCaseBase):
    id: str
    created_at: datetime

    class Config:
        from_attributes = True


class TestSuiteBase(BaseModel):
    name: str = Field(..., max_length=200)
    description: Optional[str] = None


class TestSuiteCreate(TestSuiteBase):
    cases: List[TestCaseCreate] = Field(default_factory=list)


class TestSuiteUpdate(BaseModel):
    name: Optional[str] = Field(default=None, max_length=200)
    description: Optional[str] = None


class TestSuiteOut(TestSuiteBase):
    id: str
    created_at: datetime
    updated_at: datetime
    cases: List[TestCaseOut] = Field(default_factory=list)

    class Config:
        from_attributes = True


class RunCreate(BaseModel):
    suite_id: str


class RunOut(BaseModel):
    id: str
    suite_id: str
    status: str
    created_at: datetime
    started_at: Optional[datetime]
    completed_at: Optional[datetime]

    class Config:
        from_attributes = True


class RunResultOut(BaseModel):
    id: str
    run_id: str
    case_id: str
    status: str
    agent_response: Optional[str]
    score: Optional[float]
    rubric_breakdown: Optional[dict[str, Any]]
    error: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


class RunDetailOut(RunOut):
    results: List[RunResultOut] = Field(default_factory=list)
