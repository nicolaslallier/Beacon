from app.schemas.qa import TestSuiteCreate


def test_create_suite_with_case() -> None:
    payload = TestSuiteCreate(
        name="Basic",
        description="Smoke tests",
        cases=[
            {
                "name": "Greeting",
                "prompt": "Say hello",
                "expected_response": "Hello!",
                "rubric": {"must_include": ["hello"]},
            }
        ],
    )

    assert payload.name == "Basic"
    assert payload.cases[0].prompt == "Say hello"
