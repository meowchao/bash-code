#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DIALOGRC="$SCRIPT_DIR/bash-code.dialogrc"

CONFIG_DIR="$HOME/.config/bash-code"
CONFIG_FILE="$CONFIG_DIR/config"

if ! command -v dialog > /dev/null; then
  echo "dialog not found. Install it with your package manager"
  exit 1
fi

if ! command -v jq > /dev/null; then
  echo "jq not found. Install it with your package manager"
  exit 1
fi

if ! command -v curl > /dev/null; then
  echo "curl not found. Install it with your package manager"
  exit 1
fi

mkdir -p "$CONFIG_DIR"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

#---------------------------------------------------------------------------------------------------------------------------------

HOSTS=("8.8.8.8" "1.1.1.1" "208.67.222.222")

PING_COUNT=1

TIMEOUT=2

if [[ "$OSTYPE" == "darwin"* ]]; then
    PING_TIMEOUT="-t $TIMEOUT"
else
    PING_TIMEOUT="-W $TIMEOUT"
fi

ping_host() {
    local host=$1
    ping -c $PING_COUNT $PING_TIMEOUT -q "$host" > /dev/null 2>&1
    return $?
}

connection_up=0

for host in "${HOSTS[@]}"; do
    if ping_host "$host"; then
        connection_up=1
        break
    fi
done

if [ $connection_up -ne 1 ]; then
    dialog --colors --msgbox "Internet connection is DOWN" 0 0
    clear
    exit 1
fi

#---------------------------------------------------------------------------------------------------------------
set_model(){
  MODEL_CHOICE=$(dialog --colors --menu "Choose a model" 0 0 3 \
    1 "openai/gpt-oss-20b (fast, smaller)" \
    2 "openai/gpt-oss-120b (larger, stronger)" \
    3 "qwen/qwen3.6-27b (alternative)" \
    2>&1 >/dev/tty)

  case $MODEL_CHOICE in
    1) MODEL="openai/gpt-oss-20b" ;;
    2) MODEL="openai/gpt-oss-120b" ;;
    3) MODEL="qwen/qwen3.6-27b" ;;
    *) return ;;
  esac

  grep -v '^export GROQ_MODEL=' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  printf 'export GROQ_MODEL=%q\n' "$MODEL" >> "$CONFIG_FILE"

  source "$CONFIG_FILE"
  dialog --colors --msgbox "Model set to $MODEL" 0 0
}
#--------------------------------------------------------------------------------------------------------------------------------------
settings(){
  while true; do
    SETTINGS_CHOICE=$(dialog --colors --menu "Settings" 0 0 3 \
      1 "Change API Key" \
      2 "Change Model" \
      3 "Back" \
      2>&1 >/dev/tty)

    case $SETTINGS_CHOICE in
      1) set_api_key ;;
      2) set_model ;;
      3) return ;;
      *) return ;;
    esac
  done
}

#-------------------------------------------------------------------------------------------------------------------
set_api_key(){
KEY=$(dialog --colors --title "BASH-CODE" --insecure --passwordbox "Please enter your API key from GROQ get it from https://console.groq.com/keys" 0 0 3>&1 1>&2 2>&3 3>&-)

  if [[ -z "$KEY" ]]; then
    dialog --colors --msgbox "You entered nothing" 0 0
    return
  fi

  grep -v '^export GROQ_API_KEY=' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  printf 'export GROQ_API_KEY=%q\n' "$KEY" >> "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"

  source "$CONFIG_FILE"
}

#-------------------------------------------------------------------------------------------------------------------------
if [[ -z "$GROQ_API_KEY" ]]; then
  set_api_key
  if [[ -z "$GROQ_API_KEY" ]]; then
    echo "No API key provided. Exiting."
    exit 1
  fi
fi

#--------------------------------------------------------------------------------------------------------------------
chat() {
  local transcript_file
  local prompt response text err body curl_exit dialog_exit
  local model="${GROQ_MODEL:-openai/gpt-oss-20b}"

  transcript_file=$(mktemp --tmpdir bash-code-transcript.XXXXXX) || {
    dialog --colors --msgbox "Failed to create temporary transcript." 0 0
    return 1
  }

  trap 'rm -f "$transcript_file"' RETURN

  local history
  history=$(jq -n '[
    {
      role: "system",
      content: "you are Bash Code, a terminal-based assistant. Reply in plain text only. Do not simulate shell commands, prompts, or terminal output unless the user explicitly asks for a code example. Keep answers concise."
    }
  ]')

  printf '\\Start chatting. Type /clear to reset the conversation.\\\n\n' \
    > "$transcript_file"

  while true; do
    prompt=$(
      dialog \
        --colors \
        --title " Bash Code " \
        --backtitle "Model: $model" \
        --cancel-label "Back" \
        --inputbox "Enter your message:" 10 70 \
        3>&1 1>&2 2>&3
    )
    dialog_exit=$?

    if (( dialog_exit != 0 )); then
      break
    fi

    if [[ -z "${prompt//[[:space:]]/}" ]]; then
      dialog --colors --msgbox "Please enter a message." 7 40
      continue
    fi

    case "$prompt" in
      /clear)
        history=$(jq -n '[
          {
            role: "system",
            content: "you are Bash Code, a terminal-based assistant. Reply in plain text only. Do not simulate shell commands, prompts, or terminal output unless the user explicitly asks for a code example. Keep answers concise."
          }
        ]')

        printf '\\Conversation cleared.\\\n\n' > "$transcript_file"
        continue
        ;;

      /exit|/back)
        break
        ;;
    esac

    printf '\\Z1You:\\Zn\n%s\n\n' "$prompt" >> "$transcript_file"

    history=$(
      jq \
        --arg content "$prompt" \
        '. + [{"role": "user", "content": $content}]' \
        <<< "$history"
    )

    body=$(
      jq -n \
        --arg model "$model" \
        --argjson messages "$history" \
        '{
          model: $model,
          messages: $messages
        }'
    )

    dialog \
      --colors \
      --title " Bash Code " \
      --infobox "Thinking..." 5 30

    response=$(
      curl \
        --silent \
        --show-error \
        --connect-timeout 10 \
        --max-time 120 \
        --request POST \
        --header "Authorization: Bearer $GROQ_API_KEY" \
        --header "Content-Type: application/json" \
        --data "$body" \
        "https://api.groq.com/openai/v1/chat/completions" \
        2>&1
    )
    curl_exit=$?

    if (( curl_exit != 0 )); then
      text="Network error: $response"
    elif ! jq -e . >/dev/null 2>&1 <<< "$response"; then
      text="Groq returned an invalid response."
    else
      err=$(jq -r '.error.message // empty' <<< "$response")

      if [[ -n "$err" ]]; then
        text="API error: $err"
      else
        text=$(
          jq -r '.choices[0].message.content // empty' \
            <<< "$response"
        )

        if [[ -z "$text" ]]; then
          text="The model returned an empty response."
        else
          history=$(
            jq \
              --arg content "$text" \
              '. + [{"role": "assistant", "content": $content}]' \
              <<< "$history"
          )
        fi
      fi
    fi

    printf '\\Z2Assistant:\\Zn\n%s\n\n' "$text" >> "$transcript_file"

    jq -cn \
      --arg time "$(date --iso-8601=seconds)" \
      --arg model "$model" \
      --arg prompt "$prompt" \
      --arg response "$text" \
      '{
        time: $time,
        model: $model,
        prompt: $prompt,
        response: $response
      }' >> "$CONFIG_DIR/response.log"

    dialog \
      --colors \
      --title " Bash Code . Conversation " \
      --ok-label "Continue" \
      --extra-button \
      --extra-label "New Chat" \
      --cancel-label "Back" \
      --textbox "$transcript_file" 22 78

    dialog_exit=$?

    case "$dialog_exit" in
      0)
        ;;

      3)
        history=$(jq -n '[
          {
            role: "system",
            content: "you are Bash Code, a terminal-based assistant. Reply in plain text only. Do not simulate shell commands, prompts, or terminal output unless the user explicitly asks for a code example. Keep answers concise."
          }
        ]')

        printf '\\New conversation started.\\\n\n' > "$transcript_file"
        ;;

      *)
        break
        ;;
    esac
  done
}

#-------------------------------------------------------------------------------------------------------------------------------------------------------------------

while true; do
  CHOICE=$(dialog --colors --clear \
      --backtitle "BASH-CODE" \
      --title "Main Menu" \
      --menu "Below are all the available features: " 0 0 15 \
      1 "chat" \
      2 "Project Chat" \
      3 "Settings" \
      4 "Exit" \
       2>&1 > /dev/tty)

  case $CHOICE in
    1) chat ;;
    2) dialog --colors --msgbox "Not implemented yet" 0 0 ;;
    3) settings ;;
    4) clear; exit 0 ;;
    *) clear; exit 0 ;;
  esac
done
-------------------------------------------------------------------------------------------------------------------------------------------------------------------
