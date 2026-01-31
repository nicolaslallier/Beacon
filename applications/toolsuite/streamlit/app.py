import os
from typing import Any

import requests
import streamlit as st


BACKEND_URL = os.environ.get("BACKEND_URL", "http://localhost:8000")


def run_ping_tool(message: str) -> dict[str, Any]:
    response = requests.post(
        f"{BACKEND_URL}/tools/ping",
        json={"message": message},
        timeout=5,
    )
    response.raise_for_status()
    return response.json()


st.set_page_config(page_title="Toolsuite", page_icon="tools", layout="centered")
st.title("Toolsuite")
st.caption("Run small tools backed by the Python API.")

st.subheader("Ping tool")
message = st.text_input("Message", value="ping")
if st.button("Run ping", type="primary"):
    try:
        result = run_ping_tool(message)
        st.success("Tool completed")
        st.json(result)
    except requests.RequestException as exc:
        st.error(f"Tool failed: {exc}")
