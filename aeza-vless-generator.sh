#!/usr/bin/env bash

EMAIL_API_ENDPOINT="https://api.internal.temp-mail.io/api/v3/email"
AEZA_API_ENDPOINT="https://api.aeza-security.net/v2"
USER_AGENT="okhttp/5.0.0-alpha.14"
CURL_TIMEOUT=10
CURL_RETRY=5
CURL_RETRY_DELAY=3

log_message() {
  local log_level="$1"
  local message="${*:2}"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$timestamp] [$log_level] $message" | tee -a log.txt
}

process_json() {
  local response="$1"
  local filter="$2"

  if [[ -z "$response" ]]; then
    log_message "ERROR" "Empty response received"
    return 1
  fi

  echo "$response" | jq empty &>/dev/null
  if [[ $? -ne 0 ]]; then
    log_message "ERROR" "Invalid JSON response: $response"
    return 1
  fi

  echo "$response" | jq -r "$filter"
}

curl_request() {
  local url="$1"
  local method="$2"
  local data="${3:-}"
  local user_agent="${4:-}"
  shift 4

  headers=("-H" "Content-Type: application/json")
  while (($# > 0)); do
    headers+=("-H" "$1")
    shift
  done

  response=$(curl -s --connect-timeout "$CURL_TIMEOUT" \
    --retry "$CURL_RETRY" \
    --retry-delay "$CURL_RETRY_DELAY" \
    --retry-max-time "$CURL_TIMEOUT" \
    -X "$method" "$url" \
    ${user_agent:+-A "$user_agent"} \
    "${headers[@]}" \
    ${data:+-d "$data"})
  # --proxy 127.0.0.1:8080 \
  # --insecure \

  if [[ $? -ne 0 ]]; then
    log_message "ERROR" "Failed to execute curl request to $url after $CURL_RETRY retries"
    exit 1
  fi

  echo "$response"
}

get_email() {
  local response
  response=$(curl_request "$EMAIL_API_ENDPOINT/new" "POST")
  process_json "$response" '.email'
}

send_confirmation_code() {
  log_message "INFO" "Sending confirmation code request for $1"

  local data="{\"email\":\"$1\"}"
  response=$(curl_request "$AEZA_API_ENDPOINT/auth" "POST" "$data" "$USER_AGENT")

  response_code=$(process_json "$response" '.code')
  response_exception=$(process_json "$response" '.response.exception // empty')

  case "$response_code" in
    "OK")
      log_message "INFO" "Confirmation code sent to $1"
      ;;
    "BAD_REQUEST")
      if [[ "$response_exception" == "CONFIRMATION_CODE_ALREADY_SENT" ]]; then
        log_message "ERROR" "Confirmation code has already been sent to $1"
        exit 1
      else
        log_message "ERROR" "Bad request: $response"
      fi
      ;;
    *)
      log_message "ERROR" "Unknown error: $response"
      exit 1
      ;;
  esac
}

wait_for_message() {
  local email="$1"
  local max_attempts=10
  local attempt_timeout=3
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    ((attempt++))
    log_message "INFO" "Attempt $attempt: Checking for messages..."

    messages=$(curl_request "$EMAIL_API_ENDPOINT/$email/messages" "GET")

    if [[ "$messages" != "[]" ]]; then
      log_message "INFO" "Message detected"
      return 0
    fi

    sleep "$attempt_timeout"
  done

  return 1
}

get_confirmation_code() {
  local email="$1"
  local code=""

  messages=$(curl_request "$EMAIL_API_ENDPOINT/$email/messages" "GET")

  code=$(process_json "$messages" '.[] | select(.subject == "Ваш код подтверждения Aéza Security") | .body_text' | grep -oE -m1 '[0-9]{6}')
  # code=$(echo "$messages" | jq -r '.[] | select(.subject == "Ваш код подтверждения Aéza Security") | .body_text' | grep -oE -m1 '[0-9]{6}')

  if [[ -n "$code" ]]; then
    echo "$code"
    return 0
  else
    return 1
  fi
}

generate_device_id() {
  openssl rand -hex 8
}

get_api_token() {
  local email="$1"
  local code="$2"
  device_id="$3"
  local data="{\"email\":\"$email\",\"code\":\"$code\"}"
  response=$(curl_request "$AEZA_API_ENDPOINT/auth-confirm" "POST" "$data" "$USER_AGENT" "Device-Id: $device_id")
  process_json "$response" '.response.token'
}

get_free_locations_list() {
  response=$(curl_request "$AEZA_API_ENDPOINT/locations" "GET" "" "$USER_AGENT")
  free_locations=$(process_json "$response" '.response | to_entries | map(select(.value.free == true)) | .[].key')

  if [[ $? -ne 0 ]]; then
    return 1
  fi

  echo "$free_locations"
}

select_location() {
  free_locations=($(get_free_locations_list))

  if [[ ${#free_locations[@]} -eq 0 ]]; then
    return 1
  fi

  locations_with_extra=("${free_locations[@]}" "random" "exit")

  select location in "${locations_with_extra[@]}"; do
    if [[ "$location" == "random" ]]; then
      random_location=${free_locations[$((RANDOM % ${#free_locations[@]}))]}
      echo "$random_location"
      break
    elif [[ -n "$location" ]]; then
      echo "$location"
      break
    fi
  done
}

obtain_vless_key() {
  local location="$1"
  local data="{\"location\":\"$location\"}"
  local device_id="$2"
  response=$(curl_request "$AEZA_API_ENDPOINT/vpn/connect" "POST" "$data" "$USER_AGENT" "Device-Id: $device_id" "Aeza-Token: $api_token")
  process_json "$response" '.response.accessKey'
}

main() {
  log_message "INFO" "Starting script"

  log_message "INFO" "Getting free locations"
  selected_option=$(select_location)

  if [[ "$selected_option" == "exit" || -z "$selected_option" ]]; then
    log_message "INFO" "Exiting script"
    exit 0
  fi

  log_message "INFO" "Selected location: $selected_option"

  email=$(get_email)
  log_message "INFO" "Generated email: $email"

  send_confirmation_code "$email"

  if wait_for_message "$email"; then
    confirmation_code=$(get_confirmation_code "$email")
    if [[ -n "$confirmation_code" ]]; then
      log_message "INFO" "Confirmation code obtained successfully: $confirmation_code"
    else
      log_message "ERROR" "Failed to obtain confirmation code"
      exit 1
    fi
  else
    log_message "ERROR" "Failed to receive a message"
    exit 1
  fi

  device_id=$(generate_device_id)
  api_token=$(get_api_token "$email" "$confirmation_code" "$device_id")
  log_message "INFO" "API token successfully obtained: $api_token"

  vless_key=$(obtain_vless_key "$selected_option" "$device_id")
  log_message "INFO" "VLESS key successfully obtained"
  
  qrencode -t ANSI256UTF8 "$vless_key"
  printf "\nHere is your VLESS key:\n\n%s\n" "$vless_key"

  # log_message "INFO" "Script finished successfully"
}

main
