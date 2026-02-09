"""QA API endpoints."""

import logging
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.models.qa import Run, RunResult, TestCase, TestSuite
from app.schemas.qa import (
    RunCreate,
    RunDetailOut,
    RunOut,
    RunResultOut,
    TestCaseCreate,
    TestCaseOut,
    TestCaseUpdate,
    TestSuiteCreate,
    TestSuiteOut,
    TestSuiteUpdate,
)
from app.services.run_executor import execute_run_async

router = APIRouter()
logger = logging.getLogger("beacon-qa.api")


@router.get("/test-suites", response_model=list[TestSuiteOut])
def list_test_suites(db: Session = Depends(get_db)) -> list[TestSuite]:
    logger.info("list_test_suites")
    return db.query(TestSuite).all()


@router.post("/test-suites", response_model=TestSuiteOut, status_code=status.HTTP_201_CREATED)
def create_test_suite(payload: TestSuiteCreate, db: Session = Depends(get_db)) -> TestSuite:
    logger.info("create_test_suite", extra={"name": payload.name, "case_count": len(payload.cases)})
    suite = TestSuite(name=payload.name, description=payload.description)
    for case in payload.cases:
        suite.cases.append(
            TestCase(
                name=case.name,
                prompt=case.prompt,
                expected_response=case.expected_response,
                rubric=case.rubric,
            )
        )
    db.add(suite)
    db.commit()
    db.refresh(suite)
    return suite


@router.get("/test-suites/{suite_id}", response_model=TestSuiteOut)
def get_test_suite(suite_id: str, db: Session = Depends(get_db)) -> TestSuite:
    logger.info("get_test_suite", extra={"suite_id": suite_id})
    suite = db.get(TestSuite, suite_id)
    if not suite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test suite not found")
    return suite


@router.patch("/test-suites/{suite_id}", response_model=TestSuiteOut)
def update_test_suite(
    suite_id: str,
    payload: TestSuiteUpdate,
    db: Session = Depends(get_db),
) -> TestSuite:
    logger.info("update_test_suite", extra={"suite_id": suite_id})
    suite = db.get(TestSuite, suite_id)
    if not suite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test suite not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(suite, field, value)
    db.commit()
    db.refresh(suite)
    return suite


@router.delete("/test-suites/{suite_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_test_suite(suite_id: str, db: Session = Depends(get_db)) -> None:
    logger.info("delete_test_suite", extra={"suite_id": suite_id})
    suite = db.get(TestSuite, suite_id)
    if not suite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test suite not found")
    db.delete(suite)
    db.commit()


@router.post("/test-suites/{suite_id}/cases", response_model=TestCaseOut, status_code=status.HTTP_201_CREATED)
def add_test_case(
    suite_id: str,
    payload: TestCaseCreate,
    db: Session = Depends(get_db),
) -> TestCase:
    logger.info("add_test_case", extra={"suite_id": suite_id, "name": payload.name})
    suite = db.get(TestSuite, suite_id)
    if not suite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test suite not found")
    test_case = TestCase(
        suite_id=suite_id,
        name=payload.name,
        prompt=payload.prompt,
        expected_response=payload.expected_response,
        rubric=payload.rubric,
    )
    db.add(test_case)
    db.commit()
    db.refresh(test_case)
    return test_case


@router.patch("/test-cases/{case_id}", response_model=TestCaseOut)
def update_test_case(
    case_id: str,
    payload: TestCaseUpdate,
    db: Session = Depends(get_db),
) -> TestCase:
    logger.info("update_test_case", extra={"case_id": case_id})
    test_case = db.get(TestCase, case_id)
    if not test_case:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test case not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(test_case, field, value)
    db.commit()
    db.refresh(test_case)
    return test_case


@router.delete("/test-cases/{case_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_test_case(case_id: str, db: Session = Depends(get_db)) -> None:
    logger.info("delete_test_case", extra={"case_id": case_id})
    test_case = db.get(TestCase, case_id)
    if not test_case:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test case not found")
    db.delete(test_case)
    db.commit()


@router.post("/runs", response_model=RunOut, status_code=status.HTTP_201_CREATED)
def create_run(
    payload: RunCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
) -> Run:
    logger.info("create_run", extra={"suite_id": payload.suite_id})
    suite = db.get(TestSuite, payload.suite_id)
    if not suite:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Test suite not found")
    case_count = db.query(TestCase).filter(TestCase.suite_id == payload.suite_id).count()
    if case_count == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Test suite has no cases",
        )
    run = Run(suite_id=payload.suite_id, status="pending")
    db.add(run)
    db.commit()
    db.refresh(run)
    background_tasks.add_task(execute_run_async, run.id)
    return run


@router.get("/runs", response_model=list[RunOut])
def list_runs(db: Session = Depends(get_db)) -> list[Run]:
    logger.info("list_runs")
    return db.query(Run).order_by(Run.created_at.desc()).all()


@router.get("/runs/{run_id}", response_model=RunDetailOut)
def get_run(run_id: str, db: Session = Depends(get_db)) -> Run:
    logger.info("get_run", extra={"run_id": run_id})
    run = db.get(Run, run_id)
    if not run:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Run not found")
    return run


@router.get("/runs/{run_id}/results", response_model=list[RunResultOut])
def list_run_results(run_id: str, db: Session = Depends(get_db)) -> list[RunResult]:
    logger.info("list_run_results", extra={"run_id": run_id})
    run = db.get(Run, run_id)
    if not run:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Run not found")
    return run.results
