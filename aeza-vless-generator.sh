#!/usr/bin/env bash

EMAIL_API_ENDPOINT="https://api.internal.temp-mail.io/api/v3/email"
AEZA_API_ENDPOINT="https://api.aeza-security.net/v2"
USER_AGENT="okhttp/5.0.0-alpha.14"

get_email() {
  printf "%s" "$(curl -sX POST "$EMAIL_API_ENDPOINT/new" | jq -r '.email')"
}

send_auth_code() {
  # TODO: Split into smaller functions
  response=$(curl -sX POST "$AEZA_API_ENDPOINT/auth" \
    -A "$USER_AGENT" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$1\"}")
  response_code=$(jq -r '.code' <<<"$response")
  response_exception=$(jq -r '.response.exception // empty' <<<"$response")

  case "$response_code" in
    "OK")
      printf "Success: Auth code sent to %s\n" "$1"
      ;;
    "BAD_REQUEST")
      if [[ "$response_exception" == "CONFIRMATION_CODE_ALREADY_SENT" ]]; then
        printf "Auth code has already been sent\n"
      else
        printf "Bad request: %s\n" "$response"
      fi
      ;;
    *)
      printf "Unknown error: %s\n" "$response"
      ;;
  esac
}

wait_for_auth_code() {
  local email="$1"
  local code=""
  local max_attempts=10
  local attempt_timeout=3
  local attempt=0

  while [[ -z "$code" && $attempt -lt $max_attempts ]]; do
    ((attempt++))
    printf "Attempt %d: Checking for confirmation code...\n" "$attempt"

    messages=$(curl -s "$EMAIL_API_ENDPOINT/$email/messages")

    if [[ "$messages" != "[]" ]]; then
      code=$(echo "$messages" | jq -r '.[] | select(.subject == "Ваш код подтверждения Aéza Security") | .body_text' | grep -oE -m1 '[0-9]{6}')
      if [[ -n "$code" ]]; then
        printf "%s" "$code"
        return 0
      fi
    fi

    sleep "$attempt_timeout"
  done

  printf "Failed to receive confirmation code after %d attempts\n" "$max_attempts" >&2
  return 1
}

main() {
  email=$(get_email)
  send_auth_code "$email"
  auth_code=$(wait_for_auth_code "$email")
}

main
