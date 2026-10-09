"""pNEUMA Traffic Analyst: ask questions about Athens drone traffic data.

A chat app: each question goes to Cortex Analyst together with the earlier
conversation and the semantic model. Cortex replies with its reading of the
question and a SQL query; the app runs the query and shows a table, a chart
when one fits, and the SQL.

Runs inside Snowflake as the app's owner role (PNEUMA_APP), which can only
read the prod marts. That role, not this code, is what keeps AI-written SQL
from changing anything.
"""

import json

import altair as alt
import pandas as pd
import requests
import streamlit as st
from snowflake.snowpark.context import get_active_session

# Streamlit in Snowflake has two runtimes. The older "warehouse" runtime has a
# helper module (_snowflake) for calling Snowflake's APIs; the newer
# "container" runtime doesn't. Use the helper when it's there, otherwise call
# the API over HTTPS with the app's own session.
try:
    import _snowflake
except ModuleNotFoundError:
    _snowflake = None

SEMANTIC_MODEL = "@PNEUMA_PROD.SEMANTIC.SEMANTIC_MODELS/pneuma_traffic.yaml"
ANALYST_ENDPOINT = "/api/v2/cortex/analyst/message"
TIMEOUT_MS = 50_000
FACT_TABLE = "PNEUMA_PROD.MARTS.FCT_TRAJECTORY_POINTS"

# Keep in sync with the verified queries marked use_as_onboarding_question
# in semantic/pneuma_traffic.yaml.
STARTER_QUESTIONS = [
    "What time period does the data cover?",
    "How many vehicles of each type were recorded?",
    "What is the average speed by vehicle type?",
    "How did average speed change minute by minute?",
]

MAX_BAR_ROWS = 50  # more categories than this makes an unreadable bar chart

# Must be the first Streamlit call on the page.
st.set_page_config(page_title="pNEUMA Traffic Analyst", layout="wide")

session = get_active_session()


# -----------------------------------------------------------------------------
# Cortex Analyst
# -----------------------------------------------------------------------------
def ask_cortex_analyst(messages: list) -> dict:
    """Send the conversation so far to Cortex Analyst and return its reply.

    `messages` alternates user and analyst turns, so follow-up questions
    ("now just buses") are read in context. The reply's content is a list of
    parts: "text" (how Cortex understood the question), "sql" (the query to
    run) and sometimes "suggestions" (other ways to ask, when unclear).
    """
    body = {"messages": messages, "semantic_model_file": SEMANTIC_MODEL}

    if _snowflake is not None:
        response = _snowflake.send_snow_api_request(
            "POST", ANALYST_ENDPOINT, {}, {}, body, None, TIMEOUT_MS
        )
        status, content = response["status"], json.loads(response["content"])
    else:
        # Reuse the app's logged-in session: same role, no extra credentials.
        connection = session.connection
        response = requests.post(
            f"https://{connection.host}{ANALYST_ENDPOINT}",
            json=body,
            headers={
                "Authorization": f'Snowflake Token="{connection.rest.token}"',
                "Content-Type": "application/json",
            },
            timeout=TIMEOUT_MS / 1000,
        )
        status, content = response.status_code, response.json()

    if status >= 400:
        raise RuntimeError(f"Cortex Analyst error {status}: {content}")
    return content


# -----------------------------------------------------------------------------
# Data
# -----------------------------------------------------------------------------
@st.cache_data(ttl=3600)
def data_coverage():
    """Readable time span of the data, e.g. '2018-11-01, 08:00:38–08:14:48'.

    Read from the data (not hardcoded), so it stays right as files are added.
    Cached for an hour so it isn't re-queried on every click.
    """
    row = session.sql(
        f"SELECT MIN(recorded_at) AS first_at, MAX(recorded_at) AS last_at FROM {FACT_TABLE}"
    ).collect()[0]
    first, last = row["FIRST_AT"], row["LAST_AT"]
    if first is None:
        return None
    if first.date() == last.date():
        return f"{first:%Y-%m-%d}, {first:%H:%M:%S}–{last:%H:%M:%S}"
    return f"{first:%Y-%m-%d %H:%M:%S} – {last:%Y-%m-%d %H:%M:%S}"


def run_query(sql: str):
    """Run Cortex's SQL. Returns (table, None) on success or (None, error text)."""
    try:
        df = session.sql(sql).to_pandas()
    except Exception as error:  # timeouts, bad SQL, permissions: all shown to the user
        return None, str(error)

    # Snowflake decimals arrive as Python objects; turn them into real numbers
    # so they can be charted. Text columns (vehicle types, ...) stay as they are.
    for col in df.columns:
        if df[col].dtype == object:
            converted = pd.to_numeric(df[col], errors="coerce")
            if converted.notna().sum() == df[col].notna().sum():
                df[col] = converted
    return df, None


# -----------------------------------------------------------------------------
# Charts
# -----------------------------------------------------------------------------
def nice_label(column: str) -> str:
    """AVG_SPEED_KMH -> 'Avg speed kmh'."""
    return column.lower().replace("_", " ").capitalize()


def make_chart(df: pd.DataFrame):
    """Pick a chart for the result, or None when no simple chart fits.

    - first column is a time and there's a number  -> line chart
    - first column is a label and there's a number -> horizontal bar chart
    Only the first number column is drawn; the table shows the rest.
    """
    if len(df) < 2 or len(df.columns) < 2:
        return None

    first = df.columns[0]
    numbers = [c for c in df.columns[1:] if pd.api.types.is_numeric_dtype(df[c])]
    if not numbers:
        return None
    value = numbers[0]
    tooltip = [alt.Tooltip(c, title=nice_label(c)) for c in df.columns]

    if pd.api.types.is_datetime64_any_dtype(df[first]):
        return (
            alt.Chart(df)
            .mark_line(point=len(df) <= 60)
            .encode(
                x=alt.X(f"{first}:T", title=nice_label(first)),
                y=alt.Y(f"{value}:Q", title=nice_label(value)),
                tooltip=tooltip,
            )
        )

    if not pd.api.types.is_numeric_dtype(df[first]) and len(df) <= MAX_BAR_ROWS:
        return (
            alt.Chart(df)
            .mark_bar()
            .encode(
                x=alt.X(f"{value}:Q", title=nice_label(value)),
                y=alt.Y(f"{first}:N", title=nice_label(first), sort="-x"),
                tooltip=tooltip,
            )
        )

    return None


# -----------------------------------------------------------------------------
# Conversation state
# -----------------------------------------------------------------------------
def new_conversation():
    st.session_state.messages = []  # turns sent to Cortex
    st.session_state.results = {}   # message index -> (table, error); run each query once
    st.session_state.last_error = None


def queue_question(question: str):
    """Button callback: ask this question on the next run."""
    st.session_state.pending_question = question


if "messages" not in st.session_state:
    new_conversation()


# -----------------------------------------------------------------------------
# Showing an answer
# -----------------------------------------------------------------------------
def show_answer(index: int, content: list):
    for part in content:
        if part["type"] == "text":
            st.markdown(part["text"])

        elif part["type"] == "suggestions":
            st.markdown("**Did you mean one of these?**")
            for n, suggestion in enumerate(part["suggestions"]):
                st.button(
                    suggestion,
                    key=f"suggestion-{index}-{n}",
                    on_click=queue_question,
                    args=(suggestion,),
                )

        elif part["type"] == "sql":
            if index not in st.session_state.results:
                with st.spinner("Running the query..."):
                    st.session_state.results[index] = run_query(part["statement"])
            df, error = st.session_state.results[index]

            if error:
                st.error(f"The query failed: {error}")
            elif df.empty:
                coverage = data_coverage()
                st.info(
                    f"No data for that. Recordings cover {coverage}."
                    if coverage
                    else "No data for that."
                )
            else:
                chart = make_chart(df)
                if chart is not None:
                    st.altair_chart(chart, use_container_width=True)
                st.dataframe(df, hide_index=True, use_container_width=True)

            with st.expander("Show SQL"):
                st.code(part["statement"], language="sql")


# -----------------------------------------------------------------------------
# Page
# -----------------------------------------------------------------------------
with st.sidebar:
    st.header("pNEUMA Traffic Analyst")
    st.write(
        "Drone recordings of traffic in downtown Athens: every vehicle's "
        "position and speed, 25 times a second."
    )
    coverage = data_coverage()
    if coverage:
        st.caption(f"Data covers: {coverage}")
    st.button("New conversation", on_click=new_conversation, use_container_width=True)
    st.caption("Answers come from Cortex Analyst. Queries run read-only.")

st.title("Ask about Athens traffic")

for index, message in enumerate(st.session_state.messages):
    if message["role"] == "user":
        with st.chat_message("user"):
            st.markdown(message["content"][0]["text"])
    else:
        with st.chat_message("assistant"):
            show_answer(index, message["content"])

if st.session_state.last_error:
    st.error(st.session_state.last_error)
    st.session_state.last_error = None

if not st.session_state.messages:
    st.markdown("**Try one of these:**")
    for n, starter in enumerate(STARTER_QUESTIONS):
        st.button(starter, key=f"starter-{n}", on_click=queue_question, args=(starter,))

question = st.chat_input("Ask a question about the traffic data")
question = question or st.session_state.pop("pending_question", None)

if question:
    # Cortex needs the conversation to alternate: user, analyst, user, ...
    # So the question is only saved together with its answer. If the page
    # reruns while we wait (e.g. another click), nothing half-finished is kept.
    user_turn = {"role": "user", "content": [{"type": "text", "text": question}]}
    with st.chat_message("user"):
        st.markdown(question)
    try:
        with st.spinner("Asking Cortex Analyst..."):
            reply = ask_cortex_analyst(st.session_state.messages + [user_turn])
    except Exception as error:
        st.session_state.last_error = f"Couldn't get an answer: {error}"
    else:
        st.session_state.messages += [
            user_turn,
            {"role": "analyst", "content": reply["message"]["content"]},
        ]
    st.rerun()
