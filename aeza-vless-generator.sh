#!/usr/bin/env bash

EMAIL_API_ENDPOINT="https://api.internal.temp-mail.io/api/v3/email"
AEZA_API_ENDPOINT="https://api.aeza-security.net/v2"
USER_AGENT="okhttp/5.0.0-alpha.14"

set -x

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
      printf "Success: code sent to %s\n" "$1"
      ;;
    "BAD_REQUEST")
      if [[ "$response_exception" == "CONFIRMATION_CODE_ALREADY_SENT" ]]; then
        printf "Confirmation code has already been sent\n"
      else
        printf "Bad request: %s\n" "$response"
      fi
      ;;
    *)
      printf "Unknown error: %s\n" "$response"
      ;;
  esac
}

main() {
  email=$(get_email)
  send_auth_code "$email"
}

main
