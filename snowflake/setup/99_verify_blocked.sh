#!/usr/bin/env bash
# =============================================================================
# 99 · Check the setup worked: things that SHOULD BE BLOCKED
# Run with: bash snowflake/setup/99_verify_blocked.sh
#
# Each check tries something a role must NOT be allowed to do.
#   OK      Snowflake refused it, as it should
#   FAIL    it worked, so a permission is too loose
#   ??      some other error (bad connection, typo); the output is shown
# =============================================================================

check() {
    local description=$1 sql=$2 out
    # Each snow call is a new session, so secondary roles are switched off every time.
    if out=$(snow sql -q "USE SECONDARY ROLES NONE; $sql" 2>&1); then
        echo "FAIL  $description  (it worked, but should have been blocked)"
    elif grep -qiE "insufficient privileges|does not exist or not authorized|object does not exist" <<<"$out"; then
        echo "OK    $description"
    else
        echo "??    $description"
        echo "$out" | sed 's/^/      /'
    fi
}

check "Analyst cannot create tables in prod MARTS" \
      "USE ROLE PNEUMA_ANALYST; CREATE TABLE PNEUMA_PROD.MARTS.SHOULD_FAIL (id INT)"

check "Analyst cannot see the dev database" \
      "USE ROLE PNEUMA_ANALYST; USE DATABASE PNEUMA_DEV"

check "Analyst cannot read prod RAW" \
      "USE ROLE PNEUMA_ANALYST; USE SCHEMA PNEUMA_PROD.RAW"

check "Loader cannot create tables outside RAW" \
      "USE ROLE PNEUMA_LOADER; CREATE TABLE PNEUMA_DEV.MARTS.SHOULD_FAIL (id INT)"

check "Loader cannot use the transform warehouse" \
      "USE ROLE PNEUMA_LOADER; USE WAREHOUSE TRANSFORM_WH"

check "Transformer cannot load into RAW" \
      "USE ROLE PNEUMA_TRANSFORMER; CREATE TABLE PNEUMA_DEV.RAW.SHOULD_FAIL (id INT)"

check "Analyst cannot change semantic model files" \
      "USE ROLE PNEUMA_ANALYST; REMOVE @PNEUMA_PROD.SEMANTIC.SEMANTIC_MODELS/does_not_matter.yaml"

check "App role cannot create tables in prod MARTS" \
      "USE ROLE PNEUMA_APP; CREATE TABLE PNEUMA_PROD.MARTS.SHOULD_FAIL (id INT)"

check "App role cannot see the dev database" \
      "USE ROLE PNEUMA_APP; USE DATABASE PNEUMA_DEV"
