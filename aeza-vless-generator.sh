#!/usr/bin/env bash

EMAIL_API_ENDPOINT="https://api.internal.temp-mail.io/api/v3/email"
AEZA_API_ENDPOINT="https://api.aeza-security.net/v2"
USER_AGENT="okhttp/5.0.0-alpha.14"
LOG_FILE="log.txt"
CURL_RETRY_ATTEMPTS=10
CURL_MAX_TIME=10
CURL_CONNECTION_TIMEOUT=10
CURL_RETRY_MAX_TIME=120

log_message() {
  local log_level="$1"
  local message="${*:2}"
  local timestamp
  timestamp=$(date +"%d.%m.%Y %H:%M:%S")
  echo "[$timestamp] [$log_level]: $message" | tee -a "$LOG_FILE"
}

process_json() {
  local response="$1"
  local filter="$2"
  jq -r "$filter" <<<"$response"
}

curl_request() {
  local url="$1"
  local method="$2"
  shift 2
  local user_agent=""
  local headers=()
  local data=""
  local proxy=""
  local response

  while (("$#")); do
    case "$1" in
      --user-agent)
        user_agent="$2"
        shift 2
        ;;
      --header)
        headers+=("$2")
        shift 2
        ;;
      --data)
        data="$2"
        shift 2
        ;;
      --proxy)
        proxy="$2"
        shift 2
        ;;
    esac
  done

  local curl_command="curl --connect-timeout $CURL_CONNECTION_TIMEOUT --max-time $CURL_MAX_TIME --retry $CURL_RETRY_ATTEMPTS --retry-max-time $CURL_RETRY_MAX_TIME --retry-connrefused --retry-all-errors -s -X $method"

  if [[ -n "$user_agent" ]]; then
    curl_command+=" -A '$user_agent'"
  fi

  for header in "${headers[@]}"; do
    curl_command+=" -H '$header'"
  done

  if [[ -n "$data" ]]; then
    curl_command+=" --data '$data'"
    if ! [[ "${headers[*]}" =~ "Content-Type" ]]; then
      curl_command+=" -H 'Content-Type: application/json'"
    fi
  fi

  if [[ -n "$proxy" ]]; then
    curl_command+=" --proxy $proxy"
    curl_command+=" --insecure"
  fi

  curl_command+=" '$url'"
  response=$(eval "$curl_command")
  echo "$response"
}

get_free_locations_list() {
  local response
  log_message "INFO" "Getting free locations list"
  response=$(curl_request "$AEZA_API_ENDPOINT/locations" "GET" --user-agent "$USER_AGENT")
  mapfile -t free_locations < <(process_json "$response" '.response | to_entries | map(select(.value.free == true)) | .[].key')
}

select_option() {
  get_free_locations_list
  local options=("${free_locations[@]}" "random" "exit")
  select option in "${options[@]}"; do
    if [[ "$option" == "random" ]]; then
      option=${free_locations[$((RANDOM % ${#free_locations[@]}))]}
      break
    elif [[ "$option" == "exit" ]]; then
      log_message "INFO" "Exiting script"
      exit 0
    elif [[ -n "$option" ]]; then
      break
    fi
  done
}

get_email() {
  local response
  log_message "INFO" "Getting email"
  response=$(curl_request "$EMAIL_API_ENDPOINT/new" "POST")
  email=$(process_json "$response" '.email')
  log_message "INFO" "Email: $email"
}

send_confirmation_code() {
  local response
  local response_code
  local response_exception
  log_message "INFO" "Sending confirmation code request for $email"
  response=$(curl_request "$AEZA_API_ENDPOINT/auth" "POST" --user-agent "$USER_AGENT" --data "{\"email\": \"$email\"}")
  response_code=$(process_json "$response" '.code')
  response_exception=$(process_json "$response" '.response.exception // empty')

  case "$response_code" in
    "OK")
      log_message "INFO" "Confirmation code sent to $email"
      ;;
    "BAD_REQUEST")
      if [[ "$response_exception" == "CONFIRMATION_CODE_ALREADY_SENT" ]]; then
        log_message "ERROR" "Confirmation code has already been sent to $email"
        exit 1
      else
        log_message "ERROR" "Bad request: $response"
        exit 1
      fi
      ;;
    *)
      log_message "ERROR" "Unknown error: $response"
      exit 1
      ;;
  esac
}

wait_for_email_message() {
  local max_attempts=10
  local attempt_timeout=10
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    ((attempt++))
    log_message "INFO" "Attempt $attempt: Checking for messages..."
    email_response_body=$(curl_request "$EMAIL_API_ENDPOINT/$email/messages" "GET")
    if [[ "$email_response_body" != "[]" ]]; then
      return
    fi
    log_message "INFO" "No messages yet, sleeping for $attempt_timeout seconds"
    sleep "$attempt_timeout"
    attempt_timeout=$((attempt_timeout * 2))
  done

  log_message "ERROR" "Failed to receive a message"
  exit 1
}

get_confirmation_code() {
  log_message "INFO" "Getting confirmation code"
  code=$(process_json "$email_response_body" '.[] | select(.subject == "Ваш код подтверждения Aéza Security") | .body_text' | grep -oE -m1 '[0-9]{6}')
  log_message "INFO" "Confirmation code: $code"
}

generate_device_id() {
  log_message "INFO" "Generating device ID"
  device_id=$(openssl rand -hex 8)
  log_message "INFO" "Device ID: $device_id"
}

get_api_token() {
  local response
  local min_sleep_time=10
  local max_sleep_time=30
  log_message "INFO" "Getting API token"
  response=$(curl_request "$AEZA_API_ENDPOINT/auth-confirm" "POST" --user-agent "$USER_AGENT" --header "Device-Id: $device_id" --data "{\"email\": \"$email\", \"code\": \"$code\"}")
  api_token=$(process_json "$response" '.response.token')
  log_message "INFO" "API token: $api_token"
  log_message "INFO" "Sleeping for a random amount of time (from $min_sleep_time to $max_sleep_time secs)"
  sleep $((RANDOM % (max_sleep_time - min_sleep_time + 1) + min_sleep_time))
}

get_vless_key() {
  local response
  log_message "INFO" "Getting VLESS key"
  response=$(curl_request "$AEZA_API_ENDPOINT/vpn/connect" "POST" --user-agent "$USER_AGENT" --header "Device-Id: $device_id" --header "Aeza-Token: $api_token" --data "{\"location\": \"$option\"}")
  vless_key=$(process_json "$response" '.response.accessKey')
  log_message "INFO" "Got VLESS key"
}

print_vless_key() {
  echo ""
  qrencode -t ANSIUTF8 "$vless_key"
  echo ""
  log_message "INFO" "VLESS key: $vless_key"
}

main() {
  log_message "INFO" "Starting script"
  select_option
  get_email
  send_confirmation_code
  wait_for_email_message
  get_confirmation_code
  generate_device_id
  get_api_token
  get_vless_key
  print_vless_key
  log_message "INFO" "Script finished"
}

main
