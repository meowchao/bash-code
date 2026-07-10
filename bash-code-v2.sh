#!/usr/bin/env bash

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
 
# OS-specific ping flags (Linux uses -W for per-packet timeout; macOS uses -t for deadline)
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: -t sets deadline timeout in seconds
    PING_TIMEOUT="-t $TIMEOUT"
else
    # Linux/BSD: -W sets per-packet wait timeout in seconds
    PING_TIMEOUT="-W $TIMEOUT"
fi
 
# ping a host and return 0 (success) or 1 (failure)
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
    dialog --msgbox "Internet connection is DOWN" 0 0
    clear
    exit 1
fi

#---------------------------------------------------------------------------------------------------------------
set_model(){
  MODEL_CHOICE=$(dialog --menu "Choose a model" 0 0 3 \
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

  # remove  old model line then add the new one
  grep -v '^export GROQ_MODEL=' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null
  mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  printf 'export GROQ_MODEL=%q\n' "$MODEL" >> "$CONFIG_FILE"

  source "$CONFIG_FILE"
  dialog --msgbox "Model set to $MODEL" 0 0
}
#--------------------------------------------------------------------------------------------------------------------------------------
settings(){
  while true; do
    SETTINGS_CHOICE=$(dialog --menu "Settings" 0 0 3 \
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
KEY=$(dialog --title "BASH-CODE" --insecure --passwordbox "Please enter your API key from GROQ get it from https://console.groq.com/keys" 0 0 3>&1 1>&2 2>&3 3>&-)

  if [[ -z "$KEY" ]]; then
    dialog --msgbox "You entered nothing" 0 0
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
TRANSCRIPT=""
chat(){
PROMPT=$(dialog --inputbox "enter your prompt" 0 0 3>&1 1>&2 2>&3 3>&-)
inputbox_exit=$?

  if [[ $inputbox_exit -ne 0 ]]; then
    return
    
  fi
if [[ -z "$PROMPT" ]]; then
    if dialog --yes-label "GO BACK" \
              --no-label "EXIT" \
              --yesno "You entered nothing." 0 0
    then
        chat
        return
    else
      clear
      exit 0
    fi
fi
BODY=$(jq -n --arg prompt "$PROMPT" --arg model "${GROQ_MODEL:-openai/gpt-oss-20b}" \
  '{model: $model, input: $prompt}')

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $GROQ_API_KEY" \
  -H "Content-Type: application/json" \
  "https://api.groq.com/openai/v1/responses" \
  -d "$BODY")

echo "$RESPONSE" >> ./response.log
ERR=$(echo "$RESPONSE" | jq -r '.error.message // empty')
if [[ -n "$ERR" ]]; then
  TEXT="API Error: $ERR"
else
  TEXT=$(echo "$RESPONSE" | jq -r '.output[] | select(.type=="message") | .content[0].text')
fi
TRANSCRIPT+=""$USER": $PROMPT

Groq: $TEXT

----------------------------------------

"
echo "$TRANSCRIPT" > /tmp/bash-code-reposnse.txt

dialog --ok-label "Go Back" --extra-button --extra-label "Continue Chat" --title  "Groq RESPONSE" --textbox  /tmp/bash-code-reposnse.txt 0 0 >/dev/tty
  dialog_exit_code=$?
  if [ $dialog_exit_code -eq 3 ]; then
    chat
  else
    TRANSCRIPT=""    #at session end clear it out so next Chat starts fresh
fi
}



#-------------------------------------------------------------------------------------------------------------------------------------------------------------------

while true; do
  CHOICE=$(dialog --clear \
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
    2) dialog --msgbox "Not implemented yet" 0 0 ;;
    3) settings ;;
    4) clear; exit 0 ;;
    *) clear; exit 0 ;;
  esac
done
#-------------------------------------------------------------------------------------------------------------------------------------------------------------------



