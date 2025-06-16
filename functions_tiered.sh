#!/bin/bash
# Filename: functions_tiered.sh

# This function applies Dell's default dynamic fan control profile
function apply_Dell_fan_control_profile () {
  # IPMITOOL_CMD_ARGS is expected to be set globally by the main script
  # Example: IPMITOOL_CMD_ARGS="-I open" or IPMITOOL_CMD_ARGS="-I lanplus -H host -U user -P pass"
  if ipmitool $IPMITOOL_CMD_ARGS raw 0x30 0x30 0x01 0x01 > /dev/null; then
    CURRENT_FAN_CONTROL_PROFILE="Dell Default Dynamic"
  else
    CURRENT_FAN_CONTROL_PROFILE="ERROR setting Dell Default"
    echo "$(date +"%d-%m-%Y %T") - ERROR: Failed to apply Dell default fan control profile using args: $IPMITOOL_CMD_ARGS" >&2
  fi
}

# This function applies a user-specified static fan control profile
# Takes one argument: TARGET_DECIMAL_FAN_SPEED (%)
function apply_manual_fan_speed_profile () {
  local TARGET_DECIMAL_FAN_SPEED=$1
  if [[ -z "$TARGET_DECIMAL_FAN_SPEED" ]]; then
    echo "$(date +"%d-%m-%Y %T") - ERROR: No fan speed provided to apply_manual_fan_speed_profile." >&2
    CURRENT_FAN_CONTROL_PROFILE="ERROR: No speed provided"
    return 1
  fi

  local HEXADECIMAL_TARGET_FAN_SPEED
  HEXADECIMAL_TARGET_FAN_SPEED=$(convert_decimal_value_to_hexadecimal "$TARGET_DECIMAL_FAN_SPEED")

  # Disable Dell default dynamic fan control
  if ! ipmitool $IPMITOOL_CMD_ARGS raw 0x30 0x30 0x01 0x00 > /dev/null; then
    echo "$(date +"%d-%m-%Y %T") - ERROR: Failed to disable Dell dynamic fan control using args: $IPMITOOL_CMD_ARGS" >&2
    CURRENT_FAN_CONTROL_PROFILE="ERROR disabling Dell dynamic"
    return 1
  fi
  # Set user-specified static fan speed
  if ipmitool $IPMITOOL_CMD_ARGS raw 0x30 0x30 0x02 0xff "$HEXADECIMAL_TARGET_FAN_SPEED" > /dev/null; then
    CURRENT_FAN_CONTROL_PROFILE="Manual Static ($TARGET_DECIMAL_FAN_SPEED%)"
  else
    echo "$(date +"%d-%m-%Y %T") - ERROR: Failed to set manual fan speed to $TARGET_DECIMAL_FAN_SPEED% ($HEXADECIMAL_TARGET_FAN_SPEED) using args: $IPMITOOL_CMD_ARGS" >&2
    CURRENT_FAN_CONTROL_PROFILE="ERROR setting manual $TARGET_DECIMAL_FAN_SPEED%"
    apply_Dell_fan_control_profile # Safety revert
    return 1
  fi
}

function convert_decimal_value_to_hexadecimal () {
  local DECIMAL_NUMBER=$1
  local HEXADECIMAL_NUMBER=$(printf '0x%02x' $((10#$DECIMAL_NUMBER)))
  echo "$HEXADECIMAL_NUMBER"
}

function retrieve_temperatures () {
  local IPMI_SDR_DATA
  # Capture stderr to check for specific errors if needed, though 2>/dev/null suppresses it for now
  IPMI_SDR_DATA=$(ipmitool $IPMITOOL_CMD_ARGS sdr type temperature 2>/dev/null)

  if [[ -z "$IPMI_SDR_DATA" ]]; then
      echo "$(date +"%d-%m-%Y %T") - ERROR: Failed to retrieve SDR data from IPMI using args: $IPMITOOL_CMD_ARGS." >&2
      INLET_TEMPERATURE="ERR"
      CPU1_TEMPERATURE="ERR"
      CPU2_TEMPERATURE="ERR"
      EXHAUST_TEMPERATURE="ERR"
      if command -v nvidia-smi &> /dev/null; then
        GPU_TEMPERATURE=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -n 1)
        if [[ -z "$GPU_TEMPERATURE" ]]; then GPU_TEMPERATURE="ERR"; fi
      else
        GPU_TEMPERATURE="N/A" 
      fi
      return 1
  fi
  
  CPU1_TEMPERATURE=$(echo "$IPMI_SDR_DATA" | grep -E 'Temp[[:space:]]+\|[[:space:]]+[0-9a-fA-F]+h[[:space:]]+\|[[:space:]]+ok[[:space:]]+\|[[:space:]]+3\.1' | grep -Po '\d{1,3}' | tail -n 1)
  if [[ -z "$CPU1_TEMPERATURE" ]]; then CPU1_TEMPERATURE="-"; fi

  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
    CPU2_TEMPERATURE=$(echo "$IPMI_SDR_DATA" | grep -E 'Temp[[:space:]]+\|[[:space:]]+[0-9a-fA-F]+h[[:space:]]+\|[[:space:]]+ok[[:space:]]+\|[[:space:]]+3\.2' | grep -Po '\d{1,3}' | tail -n 1)
    if [[ -z "$CPU2_TEMPERATURE" ]]; then CPU2_TEMPERATURE="-"; fi
  else
    CPU2_TEMPERATURE="-"
  fi

  INLET_TEMPERATURE=$(echo "$IPMI_SDR_DATA" | grep "Inlet Temp" | grep -Po '\d{1,3}' | tail -n 1)
  if [[ -z "$INLET_TEMPERATURE" ]]; then INLET_TEMPERATURE="-"; fi

  if $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT; then
    EXHAUST_TEMPERATURE=$(echo "$IPMI_SDR_DATA" | grep "Exhaust Temp" | grep -Po '\d{1,3}' | tail -n 1)
    if [[ -z "$EXHAUST_TEMPERATURE" ]]; then EXHAUST_TEMPERATURE="-"; fi
  else
    EXHAUST_TEMPERATURE="-"
  fi

  if command -v nvidia-smi &> /dev/null; then
    GPU_TEMPERATURE=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -n 1)
    if [[ -z "$GPU_TEMPERATURE" ]]; then GPU_TEMPERATURE="-"; fi
  else
    GPU_TEMPERATURE="N/A"
  fi
}

function gracefull_exit () {
  echo ""
  echo "/!\ WARNING /!\ Script interrupted or exiting. Applying Dell default dynamic fan control profile for safety..."
  apply_Dell_fan_control_profile
  echo "Dell default dynamic fan control profile applied. Current status: $CURRENT_FAN_CONTROL_PROFILE"
  exit 0
}

function get_Dell_server_model () {
  local IPMI_FRU_COMMAND_OUTPUT
  local IPMI_FRU_STDERR
  local EXIT_CODE

  echo "Attempting to retrieve FRU data using args: $IPMITOOL_CMD_ARGS..."

  if command -v timeout &> /dev/null; then
    eval "$(timeout 5 ipmitool $IPMITOOL_CMD_ARGS fru 2> >(IPMI_FRU_STDERR=$(cat); typeset -p IPMI_FRU_STDERR) > >(IPMI_FRU_COMMAND_OUTPUT=$(cat); typeset -p IPMI_FRU_COMMAND_OUTPUT); EXIT_CODE=$? )"
  else
    echo "Timeout command not found, running ipmitool fru without timeout."
    eval "$(ipmitool $IPMITOOL_CMD_ARGS fru 2> >(IPMI_FRU_STDERR=$(cat); typeset -p IPMI_FRU_STDERR) > >(IPMI_FRU_COMMAND_OUTPUT=$(cat); typeset -p IPMI_FRU_COMMAND_OUTPUT); EXIT_CODE=$? )"
  fi

  if [[ $EXIT_CODE -ne 0 ]] || [[ -z "$IPMI_FRU_COMMAND_OUTPUT" ]]; then
    echo "$(date +"%d-%m-%Y %T") - WARNING: Failed to retrieve FRU data from IPMI or output was empty." >&2
    echo "ipmitool fru command exit code: $EXIT_CODE" >&2
    if [[ -n "$IPMI_FRU_STDERR" ]]; then echo "ipmitool fru stderr: $IPMI_FRU_STDERR" >&2
    else echo "ipmitool fru stderr: (empty)" >&2; fi
    
    if [[ "${FORCE_DELL_CHECK_SKIP}" == "true" ]]; then
        echo "FORCE_DELL_CHECK_SKIP is true. Assuming Dell server." >&2
        SERVER_MANUFACTURER="DELL"
        SERVER_MODEL="ASSUMED_R730_BY_USER_OVERRIDE"
        return 0 
    else
        SERVER_MANUFACTURER="UNKNOWN"
        SERVER_MODEL="UNKNOWN"
        echo "Set FORCE_DELL_CHECK_SKIP=true in your .env file to bypass this check if you are sure this is a Dell server." >&2
        return 1 
    fi
  fi

  SERVER_MANUFACTURER=$(echo "$IPMI_FRU_COMMAND_OUTPUT" | grep "Product Manufacturer" | awk -F ': ' '{print $2}' | head -n 1)
  SERVER_MODEL=$(echo "$IPMI_FRU_COMMAND_OUTPUT" | grep "Product Name" | awk -F ': ' '{print $2}' | head -n 1)

  if [ -z "$SERVER_MANUFACTURER" ]; then
    SERVER_MANUFACTURER=$(echo "$IPMI_FRU_COMMAND_OUTPUT" | tr -s ' ' | grep "Board Mfg" | awk -F ': ' '{print $2}' | head -n 1)
  fi
  if [ -z "$SERVER_MODEL" ]; then
    SERVER_MODEL=$(echo "$IPMI_FRU_COMMAND_OUTPUT" | tr -s ' ' | grep "Board Product" | awk -F ': ' '{print $2}' | head -n 1)
  fi

  SERVER_MANUFACTURER=$(echo "$SERVER_MANUFACTURER" | tr '[:lower:]' '[:upper:]')

  if [ -z "$SERVER_MANUFACTURER" ] || [ -z "$SERVER_MODEL" ]; then
      echo "Could not parse Manufacturer or Model from FRU data, even though command succeeded." >&2
      echo "FRU Data was:" >&2; echo "$IPMI_FRU_COMMAND_OUTPUT" >&2
      if [[ "${FORCE_DELL_CHECK_SKIP}" == "true" ]]; then
        echo "FORCE_DELL_CHECK_SKIP is true. Assuming Dell server." >&2
        SERVER_MANUFACTURER="DELL"
        SERVER_MODEL="ASSUMED_R730_BY_USER_OVERRIDE_PARSE_FAIL"
        return 0
      else
        SERVER_MANUFACTURER="UNKNOWN_PARSE_FAIL"; SERVER_MODEL="UNKNOWN_PARSE_FAIL"
        return 1
      fi
  fi
   return 0 
}