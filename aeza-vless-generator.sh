#!/usr/bin/env bash

DEPENDENCIES="curl openssl jq qrencode"
EMAIL_API_ENDPOINT="https://api.internal.temp-mail.io/api/v3/email"
AEZA_API_ENDPOINT="https://api.aeza-security.net/v2"
USER_AGENT="Dart/3.5 (dart:io)"
LOG_FILE="log.txt"
OUTPUT_DATA_FOLDER="output"

clear_screen() {
  clear
}

get_timestamp() {
  local format="$1"
  date +"$format"
}

log_message() {
  local log_level="$1"
  local message="${*:2}"
  local timestamp
  timestamp=$(get_timestamp "%d.%m.%Y %H:%M:%S")
  echo "[$timestamp] [$log_level]: $message" | tee -a "$LOG_FILE"
}

is_installed() {
  command -v "$1" >/dev/null 2>&1
}

install_dependencies() {
  local use_sudo=""
  local missing_packages=()

  if [ "$(id -u)" -ne 0 ]; then
    use_sudo="sudo"
  fi

  for pkg in $DEPENDENCIES; do
    if ! is_installed "$pkg"; then
      missing_packages+=("$pkg")
    fi
  done

  if [ ${#missing_packages[@]} -eq 0 ]; then
    return 0
  fi

  log_message "INFO" "Missing dependencies: ${missing_packages[*]}. Do you want to install them?"
  select option in "Yes" "No"; do
    case "$option" in
      "Yes")
        log_message "INFO" "Installing missing dependencies"
        break
        ;;
      "No")
        log_message "INFO" "Exiting script"
        exit 0
        ;;
    esac
  done </dev/tty

  if [ -f /etc/os-release ]; then
    . /etc/os-release

    case "$ID" in
      debian | ubuntu)
        $use_sudo apt update
        NEEDRESTART_MODE=a $use_sudo apt install -y "${missing_packages[@]}"
        ;;
      arch)
        $use_sudo pacman -Syy --noconfirm "${missing_packages[@]}"
        ;;
      fedora)
        $use_sudo dnf install -y "${missing_packages[@]}"
        ;;
      *)
        log_message "ERROR" "Unknown or unsupported distribution: $ID"
        exit 1
        ;;
    esac

    clear_screen
  else
    log_message "ERROR" "File /etc/os-release not found, unable to determine distribution"
    exit 1
  fi
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
  local json=""
  local file=""
  local proxy=""
  local response
  local retry_attempts=10
  local max_time=10
  local connection_timeout=10
  local retry_max_time=120
  local status_code=0
  local attempt=0
  local attempt_timeout=2

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
      --json)
        json="$2"
        shift 2
        ;;
      --file)
        file="$2"
        shift 2
        ;;
      --proxy)
        proxy="$2"
        shift 2
        ;;
    esac
  done

  local curl_command="curl --connect-timeout $connection_timeout --max-time $max_time --retry $retry_attempts --retry-max-time $retry_max_time --retry-connrefused --retry-all-errors -s -w '%{http_code}' -X $method"

  if [[ -n "$user_agent" ]]; then
    curl_command+=" -A '$user_agent'"
  fi

  for header in "${headers[@]}"; do
    curl_command+=" -H '$header'"
  done

  if [[ -n "$json" ]]; then
    curl_command+=" --data '$json'"
    if ! [[ "${headers[*]}" =~ "Content-Type" ]]; then
      curl_command+=" -H 'Content-Type: application/json'"
    fi
  fi

  if [[ -n "$file" ]]; then
    curl_command+=" --upload-file '$file'"
  fi

  if [[ -n "$proxy" ]]; then
    curl_command+=" --proxy $proxy"
    curl_command+=" --insecure"
  fi

  curl_command+=" '$url'"

  # TODO: Probably should be refactored, but it works for now
  while [[ $attempt -lt $retry_attempts ]]; do
    attempt=$((attempt + 1))
    response=$(eval "$curl_command")
    status_code="${response: -3}"
    body="${response:0:${#response}-3}"

    if [[ $status_code -ne 200 ]]; then
      log_message "WARNING" "Attempt $attempt received status code $status_code. Retrying..."
      sleep $((attempt_timeout * 2))
      continue
    fi

    echo "$body"
    return 0
  done

  log_message "ERROR" "Failed to receive status 200 after $retry_attempts attempts. Last response body: $body"
  exit 1
}

get_free_locations_list() {
  local response
  log_message "INFO" "Getting free locations list"
  response=$(curl_request "$AEZA_API_ENDPOINT/locations" "GET" --user-agent "$USER_AGENT")
  mapfile -t free_locations < <(process_json "$response" '.response | to_entries | map(select(.value.free == true)) | .[].key | ascii_upcase')
}

select_location() {
  get_free_locations_list
  log_message "INFO" "Select an option. Available options: ${free_locations[*]} or choose 'random' to let the script choose for you"
  local options=("${free_locations[@]}" "random" "exit")
  select option in "${options[@]}"; do
    case "$option" in
      "random")
        option=${free_locations[$((RANDOM % ${#free_locations[@]}))]}
        break
        ;;
      "exit")
        log_message "INFO" "Exiting script"
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done </dev/tty
  log_message "INFO" "Selected option: $option"
}

ask_for_email() {
  log_message "INFO" "Would you like to use a temporary email? (Recommended). Otherwise, enter your email manually"
  select option in "Yes" "No"; do
    case "$option" in
      "Yes")
        email_mode="temporary"
        get_temporary_email
        break
        ;;
      "No")
        email_mode="manual"
        get_email_from_user
        break
        ;;
    esac
  done </dev/tty
}

get_temporary_email() {
  local response
  log_message "INFO" "Getting temporary email"
  response=$(curl_request "$EMAIL_API_ENDPOINT/new" "POST")
  email=$(process_json "$response" '.email')
  log_message "INFO" "Email: $email"
}

get_email_from_user() {
  read -r -p "Enter your email (A confirmation code will be sent to it): " email </dev/tty

  if [[ -z "$email" ]]; then
    log_message "ERROR" "Email cannot be empty"
    exit 1
  fi

  log_message "INFO" "Email: $email"
}

send_confirmation_code() {
  local response
  local response_code
  local response_exception
  log_message "INFO" "Sending confirmation code request for $email"
  response=$(curl_request "$AEZA_API_ENDPOINT/auth" "POST" --user-agent "$USER_AGENT" --json "{\"email\": \"$email\"}")
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

get_confirmation_code_from_temporary_email() {
  log_message "INFO" "Getting confirmation code"
  code=$(process_json "$email_response_body" '.[] | select(.subject == "Ваш код подтверждения Aéza Security") | .body_text' | grep -oE -m1 '[0-9]{6}')
  log_message "INFO" "Confirmation code: $code"
}

get_code_from_user() {
  while true; do
    read -r -p "Enter the confirmation code from the email message: " code </dev/tty
    if [[ -n "$code" ]]; then
      break
    fi
  done
  log_message "INFO" "Confirmation code: $code"
}

get_code() {
  if [[ "$email_mode" == "temporary" ]]; then
    wait_for_email_message
    get_confirmation_code_from_temporary_email
  else
    get_code_from_user
  fi
}

generate_device_id() {
  log_message "INFO" "Generating device ID"
  device_id=$(openssl rand -hex 8 | tr '[:lower:]' '[:upper:]')
  log_message "INFO" "Device ID: $device_id"
}

get_api_token() {
  local response
  log_message "INFO" "Getting API token"
  response=$(curl_request "$AEZA_API_ENDPOINT/auth-confirm" "POST" --user-agent "$USER_AGENT" --header "Device-Id: $device_id" --json "{\"email\": \"$email\", \"code\": \"$code\"}")
  api_token=$(process_json "$response" '.response.token')
  log_message "INFO" "API token: $api_token"
}

check_available_traffic() {
  local response
  local available_traffic
  log_message "INFO" "Checking available traffic"
  response=$(curl_request "$AEZA_API_ENDPOINT/subscription/get" "GET" --user-agent "$USER_AGENT" --header "Aeza-Token: $api_token")
  available_traffic=$(process_json "$response" '.response.trafficLeft')

  if [[ "$available_traffic" -eq 0 ]]; then
    log_message "ERROR" "No available traffic for $email. Possible rate-limited. Please try using another IP or email."
    exit 1
  fi

  log_message "INFO" "Available traffic: $available_traffic"
}

decode_url() {
  local url_encoded="${1//+/ }"
  printf '%b' "${url_encoded//%/\\x}"
}

rename_vless_key() {
  local key="$1"
  local key_name
  local timestamp
  timestamp=$(get_timestamp "%d.%m.%Y")
  key_name="AEZA-${option}-${timestamp}"
  echo "${key%#*}#${key_name}"
}

get_vless_key() {
  local response
  local vless_key_raw
  local location_lowercase
  log_message "INFO" "Getting VLESS key"
  location_lowercase=$(echo "$option" | tr '[:upper:]' '[:lower:]')
  response=$(curl_request "$AEZA_API_ENDPOINT/vpn/connect" "POST" --user-agent "$USER_AGENT" --header "Device-Id: $device_id" --header "Aeza-Token: $api_token" --json "{\"location\": \"$location_lowercase\"}")
  vless_key_raw=$(process_json "$response" '.response.accessKey')
  vless_key_original=$(decode_url "$vless_key_raw")
  vless_key=$(rename_vless_key "$vless_key_original")
  log_message "INFO" "Got VLESS key"
}

save_account_data() {
  local timestamp
  timestamp=$(get_timestamp "%s")
  filename="${timestamp}_${email}.json"
  mkdir -p "$OUTPUT_DATA_FOLDER"
  jq -n \
    --arg email "$email" \
    --arg api_token "$api_token" \
    --arg device_id "$device_id" \
    --arg vless_key "$vless_key" \
    --arg location "$option" \
    '{
      email: $email,
      api_token: $api_token,
      device_id: $device_id,
      vless_key: $vless_key,
      location: $location
    }' \
    >>"$OUTPUT_DATA_FOLDER/$filename"
}

upload_account_data() {
  local download_url

  log_message "INFO" "Would you like to upload a file with account data to bashupload? Useful when using remote servers."
  select option in "Yes" "No"; do
    case "$option" in
      "Yes")
        upload_file=true
        break
        ;;
      "No")
        upload_file=false
        break
        ;;
    esac
  done </dev/tty

  if [[ "$upload_file" == true ]]; then
    log_message "INFO" "Uploading a file with account data to bashupload"
    download_url=$(curl_request "https://bashupload.com" "POST" --file "$OUTPUT_DATA_FOLDER/$filename" | grep -oP 'https://bashupload\.com/\S+')
    direct_download_url="$download_url?download=1"
    log_message "INFO" "Successfully uploaded the account data file to bashupload"
  fi
}

print_vless_key() {
  qrencode -t ANSIUTF8 "$vless_key"
  echo ""
  log_message "INFO" "VLESS key: $vless_key"
  echo ""

  if [[ "$upload_file" == true ]]; then
    log_message "INFO" "One-time download link: $direct_download_url"
  fi
}

main() {
  log_message "INFO" "Script started"
  install_dependencies
  ask_for_email
  send_confirmation_code
  get_code
  generate_device_id
  get_api_token
  check_available_traffic
  select_location
  get_vless_key
  save_account_data
  upload_account_data
  clear_screen
  print_vless_key
  log_message "INFO" "Script finished"
}

main
