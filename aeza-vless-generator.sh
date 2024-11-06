#!/usr/bin/env bash

EMAIL_API_ENDPOINT="https://api.internal.temp-mail.io/api/v3/email"

get_email() {
  printf "%s" "$(curl -sX POST "$EMAIL_API_ENDPOINT/new" | jq -r '.email')"
}

main() {
  email=$(get_email)
}

main
