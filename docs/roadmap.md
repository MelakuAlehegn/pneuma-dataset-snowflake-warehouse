# Roadmap

What's done and what's left. Details of finished steps are in [worklog.md](worklog.md).

| # | Step | Status |
|---|------|--------|
| 1 | Platform foundation: CLI, roles, warehouses, dev/prod databases, permissions | Done |
| 2 | Load raw pNEUMA file into RAW | Done |
| 3 | dbt on Snowflake: staging, intermediate, marts | Done |
| 4 | Cortex Analyst semantic model (YAML) with verified queries | Done |
| 5 | Streamlit chat app (owned and run by a read-only role) | Done |
| 5c | Conversation history in the app's sidebar | Next |
| 6 | Automation: scheduled Tasks that load new files and run dbt in prod; refresh dev as a zero-copy clone of prod | To do |
| 8 | Admin polish: test user with only the analyst role; resource monitor (credit budget); query history and cost views | To do |
| 9 | Demo: README with architecture diagram and screenshots; recording | To do |
| — | Email alerts on failures | Only if needed, at the end |

**Out of scope (decided 2026-10-10):** evals (old step 7), loading more pNEUMA files, map grid for "where" questions.

**Open decision for 5c:** keep history for this visit only (stays fully read-only), or save it in a table (app role needs write access to one table).
