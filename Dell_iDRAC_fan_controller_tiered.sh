#!/bin/bash
# Filename: Dell_iDRAC_fan_controller_tiered.sh (v5)

# Load environment variables from .env file
if [ -f .env ]; then
  source .env
else
  echo "Warning: .env file not found. Using default/example values. Please configure them."
  # Default values (ensure these match your desired defaults)
  CPU_TEMP_THRESHOLD_TIER1=${CPU_TEMP_THRESHOLD_TIER1:-50} # Upper bound for Tier 1
  CPU_TEMP_THRESHOLD_TIER2=${CPU_TEMP_THRESHOLD_TIER2:-60} # Upper bound for Tier 2
  CPU_TEMP_THRESHOLD_TIER3=${CPU_TEMP_THRESHOLD_TIER3:-70} # Upper bound for Tier 3
  CPU_TEMP_THRESHOLD_TIER4=${CPU_TEMP_THRESHOLD_TIER4:-78} # Upper bound for Tier 4 (Critical above this)

  GPU_TEMP_THRESHOLD_TIER1=${GPU_TEMP_THRESHOLD_TIER1:-48} # Upper bound for Tier 1
  GPU_TEMP_THRESHOLD_TIER2=${GPU_TEMP_THRESHOLD_TIER2:-58} # Upper bound for Tier 2
  GPU_TEMP_THRESHOLD_TIER3=${GPU_TEMP_THRESHOLD_TIER3:-68} # Upper bound for Tier 3
  GPU_TEMP_THRESHOLD_TIER4=${GPU_TEMP_THRESHOLD_TIER4:-76} # Upper bound for Tier 4 (Critical above this)

  FAN_SPEED_TIER1=${FAN_SPEED_TIER1:-12}
  FAN_SPEED_TIER2=${FAN_SPEED_TIER2:-22}
  FAN_SPEED_TIER3=${FAN_SPEED_TIER3:-38}
  FAN_SPEED_TIER4=${FAN_SPEED_TIER4:-55}

  CHECK_INTERVAL=${CHECK_INTERVAL:-10}
  HYSTERESIS_TEMP=${HYSTERESIS_TEMP:-3} # Default hysteresis to 3 degrees C if not set
  FORCE_DELL_CHECK_SKIP=${FORCE_DELL_CHECK_SKIP:-false}
  SCRIPT_VERBOSITY=${SCRIPT_VERBOSITY:-normal}
fi

# Set defaults if not defined in .env
SCRIPT_VERBOSITY=${SCRIPT_VERBOSITY:-normal}
HYSTERESIS_TEMP=${HYSTERESIS_TEMP:-3} # Ensure hysteresis has a default

export IPMITOOL_CMD_ARGS

if [[ "$IDRAC_HOST" == "local" ]]; then
  if [ ! -e "/dev/ipmi0" ] && [ ! -e "/dev/ipmi/0" ] && [ ! -e "/dev/ipmidev/0" ]; then
    echo "/!\ Could not open device at /dev/ipmi0 or /dev/ipmi/0 or /dev/ipmidev/0. Exiting." >&2
    exit 1
  fi
  IPMITOOL_CMD_ARGS="-I open"
  echo "Using local iDRAC access."
else
  if [[ -z "$IDRAC_USERNAME" ]] || [[ -z "$IDRAC_PASSWORD" ]]; then
    echo "/!\ IDRAC_USERNAME or IDRAC_PASSWORD is not set for remote iDRAC access. Exiting." >&2
    exit 1
  fi
  echo "Using remote iDRAC access: Host=$IDRAC_HOST, User=$IDRAC_USERNAME"
  IPMITOOL_CMD_ARGS="-I lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
fi

source functions_tiered.sh # Assuming functions_tiered.sh is v3

trap 'gracefull_exit' SIGINT SIGQUIT SIGKILL SIGTERM

if ! get_Dell_server_model; then
    if [[ "${FORCE_DELL_CHECK_SKIP}" != "true" ]]; then
        echo "/!\ Exiting due to server model check failure. Set FORCE_DELL_CHECK_SKIP=true to bypass." >&2
        exit 1
    fi
    echo "WARNING: Server model check failed but FORCE_DELL_CHECK_SKIP is true. Proceeding."
fi

if [[ "$SERVER_MANUFACTURER" != "DELL" ]]; then
  echo "/!\ Server is not Dell ($SERVER_MANUFACTURER $SERVER_MODEL) or check failed. Exiting." >&2
  exit 1
fi

echo "Server model: $SERVER_MANUFACTURER $SERVER_MODEL"
echo "iDRAC/IPMI connection: $IDRAC_HOST"
echo "Script verbosity: $SCRIPT_VERBOSITY"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Hysteresis: ${HYSTERESIS_TEMP}C"
echo ""
echo "CPU Temp Thresholds (C): T1<=$CPU_TEMP_THRESHOLD_TIER1 < T2<=$CPU_TEMP_THRESHOLD_TIER2 < T3<=$CPU_TEMP_THRESHOLD_TIER3 < T4<=$CPU_TEMP_THRESHOLD_TIER4 < Critical"
echo "GPU Temp Thresholds (C): T1<=$GPU_TEMP_THRESHOLD_TIER1 < T2<=$GPU_TEMP_THRESHOLD_TIER2 < T3<=$GPU_TEMP_THRESHOLD_TIER3 < T4<=$GPU_TEMP_THRESHOLD_TIER4 < Critical"
echo "Fan Speeds (%): T1=$FAN_SPEED_TIER1, T2=$FAN_SPEED_TIER2, T3=$FAN_SPEED_TIER3, T4=$FAN_SPEED_TIER4"
echo ""

CURRENT_MANUAL_PROFILE_ACTIVE=false
LAST_SET_MANUAL_SPEED_DECIMAL=""
CURRENT_ACTIVE_TIER=0 # 0=Unknown, 1-4=Manual Tiers, 5=Dell Default
# Initialize CURRENT_FAN_CONTROL_PROFILE to avoid issues on first PREVIOUS_ capture
CURRENT_FAN_CONTROL_PROFILE="Initializing..."


IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU2_TEMPERATURE_SENSOR_PRESENT=true
retrieve_temperatures # Initial check

readonly TABLE_HEADER_PRINT_INTERVAL=10
print_counter=$TABLE_HEADER_PRINT_INTERVAL

while true; do
  sleep $CHECK_INTERVAL &
  SLEEP_PROCESS_PID=$!

  # Capture state BEFORE any potential changes for accurate "previous state" logging
  PREVIOUS_CURRENT_ACTIVE_TIER=$CURRENT_ACTIVE_TIER
  PREVIOUS_FAN_CONTROL_PROFILE_FOR_EVENT_LOG="$CURRENT_FAN_CONTROL_PROFILE"
  PREVIOUS_LAST_SET_MANUAL_SPEED_DECIMAL_FOR_EVENT_LOG="$LAST_SET_MANUAL_SPEED_DECIMAL"

  retrieve_temperatures

  # Determine the highest tier any component *wants* to be in based on exceeding upper thresholds
  REQUIRED_TIER_CPU1=1
  if [[ "$CPU1_TEMPERATURE" != "-" && "$CPU1_TEMPERATURE" != "ERR" ]]; then
    if (( $(echo "$CPU1_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER4" | bc -l) )); then REQUIRED_TIER_CPU1=5
    elif (( $(echo "$CPU1_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER3" | bc -l) )); then REQUIRED_TIER_CPU1=4
    elif (( $(echo "$CPU1_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER2" | bc -l) )); then REQUIRED_TIER_CPU1=3
    elif (( $(echo "$CPU1_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER1" | bc -l) )); then REQUIRED_TIER_CPU1=2
    fi
  fi

  REQUIRED_TIER_GPU=1
  if [[ "$GPU_TEMPERATURE" != "-" && "$GPU_TEMPERATURE" != "ERR" && "$GPU_TEMPERATURE" != "N/A" ]]; then
    if (( $(echo "$GPU_TEMPERATURE > $GPU_TEMP_THRESHOLD_TIER4" | bc -l) )); then REQUIRED_TIER_GPU=5
    elif (( $(echo "$GPU_TEMPERATURE > $GPU_TEMP_THRESHOLD_TIER3" | bc -l) )); then REQUIRED_TIER_GPU=4
    elif (( $(echo "$GPU_TEMPERATURE > $GPU_TEMP_THRESHOLD_TIER2" | bc -l) )); then REQUIRED_TIER_GPU=3
    elif (( $(echo "$GPU_TEMPERATURE > $GPU_TEMP_THRESHOLD_TIER1" | bc -l) )); then REQUIRED_TIER_GPU=2
    fi
  fi

  REQUIRED_TIER_CPU2=1
  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && [[ "$CPU2_TEMPERATURE" != "-" && "$CPU2_TEMPERATURE" != "ERR" ]]; then
    if (( $(echo "$CPU2_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER4" | bc -l) )); then REQUIRED_TIER_CPU2=5
    elif (( $(echo "$CPU2_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER3" | bc -l) )); then REQUIRED_TIER_CPU2=4
    elif (( $(echo "$CPU2_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER2" | bc -l) )); then REQUIRED_TIER_CPU2=3
    elif (( $(echo "$CPU2_TEMPERATURE > $CPU_TEMP_THRESHOLD_TIER1" | bc -l) )); then REQUIRED_TIER_CPU2=2
    fi
  fi

  # This is the highest tier any component is pushing for (potential upward move)
  POTENTIAL_UPWARD_TARGET_TIER=$REQUIRED_TIER_CPU1
  if [[ $REQUIRED_TIER_GPU -gt $POTENTIAL_UPWARD_TARGET_TIER ]]; then POTENTIAL_UPWARD_TARGET_TIER=$REQUIRED_TIER_GPU; fi
  if [[ $REQUIRED_TIER_CPU2 -gt $POTENTIAL_UPWARD_TARGET_TIER ]]; then POTENTIAL_UPWARD_TARGET_TIER=$REQUIRED_TIER_CPU2; fi

  FINAL_TARGET_TIER=$CURRENT_ACTIVE_TIER # Assume no change initially

  if [[ $POTENTIAL_UPWARD_TARGET_TIER -gt $CURRENT_ACTIVE_TIER ]]; then
    # Temperature increase demands a higher tier
    FINAL_TARGET_TIER=$POTENTIAL_UPWARD_TARGET_TIER
  elif [[ $POTENTIAL_UPWARD_TARGET_TIER -lt $CURRENT_ACTIVE_TIER && $CURRENT_ACTIVE_TIER -ne 5 && $CURRENT_ACTIVE_TIER -ne 0 ]]; then
    # Temps suggest we *could* slow down from a manual tier. Apply hysteresis.
    # To drop from CURRENT_ACTIVE_TIER to POTENTIAL_UPWARD_TARGET_TIER, all components must be cool enough.
    CAN_DECREASE_TIER=true
    # What is the threshold that triggered the CURRENT_ACTIVE_TIER?
    # E.g., if CURRENT_ACTIVE_TIER is 3, it was triggered by exceeding THRESHOLD_TIER2.
    # We need to drop below (THRESHOLD_TIER2 - HYSTERESIS_TEMP) to go to Tier 2.
    
    # Check CPU1
    TARGET_LOWER_THRESHOLD_CPU1=""
    if [[ $CURRENT_ACTIVE_TIER -eq 2 ]]; then TARGET_LOWER_THRESHOLD_CPU1=$CPU_TEMP_THRESHOLD_TIER1;
    elif [[ $CURRENT_ACTIVE_TIER -eq 3 ]]; then TARGET_LOWER_THRESHOLD_CPU1=$CPU_TEMP_THRESHOLD_TIER2;
    elif [[ $CURRENT_ACTIVE_TIER -eq 4 ]]; then TARGET_LOWER_THRESHOLD_CPU1=$CPU_TEMP_THRESHOLD_TIER3;
    fi
    if [[ -n "$TARGET_LOWER_THRESHOLD_CPU1" && "$CPU1_TEMPERATURE" != "-" && "$CPU1_TEMPERATURE" != "ERR" ]]; then
      if (( $(echo "$CPU1_TEMPERATURE >= ($TARGET_LOWER_THRESHOLD_CPU1 - $HYSTERESIS_TEMP)" | bc -l) )); then
        CAN_DECREASE_TIER=false # CPU1 still too warm to allow decrease
      fi
    fi

    # Check GPU
    TARGET_LOWER_THRESHOLD_GPU=""
    if [[ $CURRENT_ACTIVE_TIER -eq 2 ]]; then TARGET_LOWER_THRESHOLD_GPU=$GPU_TEMP_THRESHOLD_TIER1;
    elif [[ $CURRENT_ACTIVE_TIER -eq 3 ]]; then TARGET_LOWER_THRESHOLD_GPU=$GPU_TEMP_THRESHOLD_TIER2;
    elif [[ $CURRENT_ACTIVE_TIER -eq 4 ]]; then TARGET_LOWER_THRESHOLD_GPU=$GPU_TEMP_THRESHOLD_TIER3;
    fi
     if $CAN_DECREASE_TIER && [[ -n "$TARGET_LOWER_THRESHOLD_GPU" && "$GPU_TEMPERATURE" != "-" && "$GPU_TEMPERATURE" != "ERR" && "$GPU_TEMPERATURE" != "N/A" ]]; then
      if (( $(echo "$GPU_TEMPERATURE >= ($TARGET_LOWER_THRESHOLD_GPU - $HYSTERESIS_TEMP)" | bc -l) )); then
        CAN_DECREASE_TIER=false # GPU still too warm
      fi
    fi
    
    # Check CPU2
    TARGET_LOWER_THRESHOLD_CPU2=""
    if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
        if [[ $CURRENT_ACTIVE_TIER -eq 2 ]]; then TARGET_LOWER_THRESHOLD_CPU2=$CPU_TEMP_THRESHOLD_TIER1;
        elif [[ $CURRENT_ACTIVE_TIER -eq 3 ]]; then TARGET_LOWER_THRESHOLD_CPU2=$CPU_TEMP_THRESHOLD_TIER2;
        elif [[ $CURRENT_ACTIVE_TIER -eq 4 ]]; then TARGET_LOWER_THRESHOLD_CPU2=$CPU_TEMP_THRESHOLD_TIER3;
        fi
    fi
    if $CAN_DECREASE_TIER && [[ -n "$TARGET_LOWER_THRESHOLD_CPU2" && "$CPU2_TEMPERATURE" != "-" && "$CPU2_TEMPERATURE" != "ERR" ]]; then
        if (( $(echo "$CPU2_TEMPERATURE >= ($TARGET_LOWER_THRESHOLD_CPU2 - $HYSTERESIS_TEMP)" | bc -l) )); then
            CAN_DECREASE_TIER=false # CPU2 still too warm
        fi
    fi

    if $CAN_DECREASE_TIER; then
      # All relevant components are cool enough to allow the drop to the highest tier still required by any component
      FINAL_TARGET_TIER=$POTENTIAL_UPWARD_TARGET_TIER 
    else
      FINAL_TARGET_TIER=$CURRENT_ACTIVE_TIER # Cannot decrease, maintain current tier
    fi
  fi
  
  # Override to Dell Default if any component is in critical tier (Tier 5)
  if [[ $REQUIRED_TIER_CPU1 -eq 5 || $REQUIRED_TIER_GPU -eq 5 || $REQUIRED_TIER_CPU2 -eq 5 ]]; then
    FINAL_TARGET_TIER=5
  fi

  # If FINAL_TARGET_TIER is still 0 (initial run and all temps very low), set to Tier 1
  if [[ $FINAL_TARGET_TIER -eq 0 ]]; then
      FINAL_TARGET_TIER=1
  fi

  LOG_COMMENT_FOR_TABLE="" # For the full status table if verbosity=normal

  # Act based on FINAL_TARGET_TIER
  if [[ $FINAL_TARGET_TIER -eq 5 ]]; then # Critical Temperature
    if [[ $CURRENT_ACTIVE_TIER -ne 5 || $CURRENT_MANUAL_PROFILE_ACTIVE == true ]]; then
      apply_Dell_fan_control_profile
      LOG_COMMENT_FOR_TABLE="CRITICAL->Dell Default. CPU1:${CPU1_TEMPERATURE}C,GPU:${GPU_TEMPERATURE}C"
      if [[ "$SCRIPT_VERBOSITY" == "quiet" || "$CURRENT_FAN_CONTROL_PROFILE" != "$PREVIOUS_FAN_CONTROL_PROFILE_FOR_EVENT_LOG" ]]; then
        echo "$(date +"%d-%m-%Y %T") [CRITICAL EVENT] Dell default dynamic fan control profile APPLIED. Temps - CPU1:${CPU1_TEMPERATURE}C CPU2:${CPU2_TEMPERATURE}C GPU:${GPU_TEMPERATURE}C. Prev: $PREVIOUS_FAN_CONTROL_PROFILE_FOR_EVENT_LOG"
      fi
      CURRENT_MANUAL_PROFILE_ACTIVE=false
      LAST_SET_MANUAL_SPEED_DECIMAL="" # Reset as we are not in manual mode
      CURRENT_ACTIVE_TIER=5
    else
      LOG_COMMENT_FOR_TABLE="CRITICAL! Dell dynamic profile remains active."
    fi
  else # Manual Tier 1-4
    NEW_FAN_SPEED_DECIMAL=""
    case $FINAL_TARGET_TIER in
      1) NEW_FAN_SPEED_DECIMAL=$FAN_SPEED_TIER1 ;;
      2) NEW_FAN_SPEED_DECIMAL=$FAN_SPEED_TIER2 ;;
      3) NEW_FAN_SPEED_DECIMAL=$FAN_SPEED_TIER3 ;;
      4) NEW_FAN_SPEED_DECIMAL=$FAN_SPEED_TIER4 ;;
    esac

    # Only apply if the target tier is different, or if we're switching from Dell Default, or if the speed for the same tier somehow changed (e.g. .env edit)
    if [[ $FINAL_TARGET_TIER -ne $PREVIOUS_CURRENT_ACTIVE_TIER || \
          $CURRENT_MANUAL_PROFILE_ACTIVE == false || \
          "$NEW_FAN_SPEED_DECIMAL" != "$LAST_SET_MANUAL_SPEED_DECIMAL" ]]; then
      apply_manual_fan_speed_profile "$NEW_FAN_SPEED_DECIMAL"
      LOG_COMMENT_FOR_TABLE="Tier $FINAL_TARGET_TIER. Manual fan $NEW_FAN_SPEED_DECIMAL%."
      if [[ "$SCRIPT_VERBOSITY" == "quiet" || "$NEW_FAN_SPEED_DECIMAL" != "$PREVIOUS_LAST_SET_MANUAL_SPEED_DECIMAL_FOR_EVENT_LOG" || $PREVIOUS_CURRENT_ACTIVE_TIER -ne $FINAL_TARGET_TIER ]]; then
          echo "$(date +"%d-%m-%Y %T") [FAN CHANGE EVENT] Set manual fan to $NEW_FAN_SPEED_DECIMAL% (Tier $FINAL_TARGET_TIER). Prev: $PREVIOUS_FAN_CONTROL_PROFILE_FOR_EVENT_LOG ($PREVIOUS_LAST_SET_MANUAL_SPEED_DECIMAL_FOR_EVENT_LOG%)"
      fi
      CURRENT_MANUAL_PROFILE_ACTIVE=true
      LAST_SET_MANUAL_SPEED_DECIMAL="$NEW_FAN_SPEED_DECIMAL"
      CURRENT_ACTIVE_TIER=$FINAL_TARGET_TIER
    else
      LOG_COMMENT_FOR_TABLE="Tier $FINAL_TARGET_TIER ($LAST_SET_MANUAL_SPEED_DECIMAL%) maintained."
    fi
  fi

  if [[ "$SCRIPT_VERBOSITY" == "normal" ]]; then
    if [ $print_counter -ge $TABLE_HEADER_PRINT_INTERVAL ]; then
      echo "-------------------------------- Temperature and Fan Control ---------------------------------"
      echo "    Date & Time     | Inlet C | CPU1 C  | CPU2 C  | Exhaust C | GPU C   | Active Profile / Target Speed (%) | Comment"
      echo "--------------------|---------|---------|---------|-----------|---------|-----------------------------------|-----------------------------------"
      print_counter=0
    fi
    printf "%-19s | %-7s | %-7s | %-7s | %-9s | %-7s | %-33s | %s\n" \
      "$(date +"%d-%m-%Y %T")" "$INLET_TEMPERATURE" "$CPU1_TEMPERATURE" "$CPU2_TEMPERATURE" \
      "$EXHAUST_TEMPERATURE" "$GPU_TEMPERATURE" "$CURRENT_FAN_CONTROL_PROFILE" "$LOG_COMMENT_FOR_TABLE"
    ((print_counter++))
  fi
  wait $SLEEP_PROCESS_PID
done