#!/bin/bash
# Contract G-5 regression check: bash slugify must match the canonical JS
# slugify (bootstrap.js:109): lower | [^a-z0-9]+ -> "-" | trim "-".
# Guards the H11 lockout fix: a non-slug location/host must be coerced to the
# same slug the directory actually creates, or the host is silently locked out.
slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-|-$//g'
}

# input -> expected (taken verbatim from canonical JS slugify)
pairs=(
  "|"
  "nyc|nyc"
  "NYC|nyc"
  "New York|new-york"
  "web-01|web-01"
  "web_01|web-01"
  "host.name|host-name"
  "a__b|a-b"
  "---x---|x"
  "UPPER.case  here|upper-case-here"
  "_leading|leading"
  "trailing_|trailing"
  "  spaces  |spaces"
  "foo--bar|foo-bar"
  "123|123"
  "ALL|all"
)

fail=0
for pair in "${pairs[@]}"; do
  input="${pair%%|*}"
  want="${pair##*|}"
  got="$(slugify "$input")"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: slugify($(printf '%q' \"\$input\")) = $(printf '%q' \"\$got\"), want $(printf '%q' \"\$want\")"
    fail=1
  fi
done

# Extra: embedded quote / backslash must be stripped without breaking the shell.
got="$(slugify "o'")"
[[ "$got" == "o" ]] || { echo "FAIL: quote case got $(printf '%q' \"$got\")"; fail=1; }

if [[ "$fail" -eq 0 ]]; then
  echo "ALL SLUG CASES PASS"
else
  echo "SLUG CASES FAILED"
  exit 1
fi
