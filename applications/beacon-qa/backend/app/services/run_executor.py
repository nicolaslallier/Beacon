"""Run execution service."""

import logging
from datetime import datetime, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.core.database import SessionLocal
from app.models.qa import Run, RunResult, TestCase
from app.core.config import settings
from app.services.n8n_client import execute_webhook, execute_workflow_api

logger = logging.getLogger(__name__)


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _extract_response(
    data: dict[str, Any],
) -> tuple[str | None, float | None, dict | None]:
    """Normalize N8N response fields."""
    agent_response = (
        data.get("agent_response")
        or data.get("answer")
        or data.get("response")
    )
    score = data.get("score")
    rubric_breakdown = (
        data.get("rubric_breakdown")
        or data.get("rubric")
        or data.get("scores")
    )
    return agent_response, score, rubric_breakdown


def execute_run_async(run_id: str) -> None:
    """Execute test run in the background."""
    db: Session = SessionLocal()
    try:
        run = db.get(Run, run_id)
        if not run:
            logger.warning("run_not_found", extra={"run_id": run_id})
            return
        logger.info(
            "run_start",
            extra={"run_id": run.id, "suite_id": run.suite_id},
        )
        run.status = "running"
        run.started_at = _utc_now()
        db.commit()

        cases = (
            db.query(TestCase)
            .filter(TestCase.suite_id == run.suite_id)
            .order_by(TestCase.created_at.asc())
            .all()
        )
        failed = False

        for case in cases:
            logger.info(
                "run_case_start",
                extra={
                    "run_id": run.id,
                    "case_id": case.id,
                    "case_name": case.name,
                },
            )
            result = RunResult(
                run_id=run.id,
                case_id=case.id,
                status="running",
            )
            db.add(result)
            db.commit()
            db.refresh(result)

            payload = {
                "test_case_id": case.id,
                "suite_id": case.suite_id,
                "prompt": case.prompt,
                "expected_response": case.expected_response,
                "rubric": case.rubric,
            }
            try:
                if settings.n8n_mode == "api":
                    if not settings.n8n_workflow_id:
                        raise ValueError("N8N_WORKFLOW_ID is not set")
                    response = execute_workflow_api(
                        settings.n8n_workflow_id,
                        payload,
                    )
                else:
                    response = execute_webhook(payload)
                agent_response, score, rubric_breakdown = _extract_response(response)
                result.agent_response = agent_response
                result.score = score
                result.rubric_breakdown = rubric_breakdown
                result.status = "completed"
                logger.info(
                    "run_case_complete",
                    extra={
                        "run_id": run.id,
                        "case_id": case.id,
                        "score": score,
                    },
                )
            except Exception as exc:
                failed = True
                result.status = "failed"
                result.error = str(exc)
                logger.exception(
                    "run_case_failed",
                    extra={"run_id": run.id, "case_id": case.id},
                )
            db.commit()

        run.status = "completed_with_errors" if failed else "completed"
        run.completed_at = _utc_now()
        db.commit()
        logger.info(
            "run_complete",
            extra={"run_id": run.id, "status": run.status},
        )
    finally:
        db.close()
