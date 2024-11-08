#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
  source .env
else
  echo "Warning: .env file not found. Make sure to set environment variables manually."
fi

# Enable strict bash mode to stop the script if an uninitialized variable is used, if a command fails, or if a command with a pipe fails
# Not working in some setups : https://github.com/tigerblue77/Dell_iDRAC_fan_controller/issues/48
# set -euo pipefail

source functions.sh

# Trap the signals for container exit and run gracefull_exit function
trap 'gracefull_exit' SIGINT SIGQUIT SIGKILL SIGTERM

# Prepare, format and define initial variables

# Check if FAN_SPEED variable is in hexadecimal format. If not, convert it to hexadecimal
if [[ $FAN_SPEED == 0x* ]]
then
  readonly DECIMAL_FAN_SPEED=$(printf '%d' $FAN_SPEED)
  readonly HEXADECIMAL_FAN_SPEED=$FAN_SPEED
else
  readonly DECIMAL_FAN_SPEED=$FAN_SPEED
  readonly HEXADECIMAL_FAN_SPEED=$(convert_decimal_value_to_hexadecimal $FAN_SPEED)
fi

# Check if the iDRAC host is set to 'local' or not then set the IDRAC_LOGIN_STRING accordingly
if [[ $IDRAC_HOST == "local" ]]
then
  # Check that the IPMI device (the iDRAC) has been exposed to the Docker container
  if [ ! -e "/dev/ipmi0" ] && [ ! -e "/dev/ipmi/0" ] && [ ! -e "/dev/ipmidev/0" ]; then
    echo "/!\ Could not open device at /dev/ipmi0 or /dev/ipmi/0 or /dev/ipmidev/0, check that you have installed ipmitools. Exiting." >&2
    exit 1
  fi
  IDRAC_LOGIN_STRING='open'
else
  echo "iDRAC/IPMI username: $IDRAC_USERNAME"
  echo "iDRAC/IPMI password: $IDRAC_PASSWORD"
  IDRAC_LOGIN_STRING="lanplus -H $IDRAC_HOST -U $IDRAC_USERNAME -P $IDRAC_PASSWORD"
fi

get_Dell_server_model

if [[ ! $SERVER_MANUFACTURER == "DELL" ]]
then
  echo "/!\ Your server isn't a Dell product. Exiting." >&2
  exit 1
fi

# Log main informations
echo "Server model: $SERVER_MANUFACTURER $SERVER_MODEL"
echo "iDRAC/IPMI host: $IDRAC_HOST"

# Log the fan speed objective, CPU temperature threshold and check interval
echo "Fan speed objective: $DECIMAL_FAN_SPEED%"
echo "CPU temperature threshold: $CPU_TEMPERATURE_THRESHOLDÂ°C"
echo "GPU temperature threshold: $GPU_TEMPERATURE_THRESHOLDÂ°C"
echo "Check interval: ${CHECK_INTERVAL}s"
echo ""

# Define the interval for printing
readonly TABLE_HEADER_PRINT_INTERVAL=10
i=$TABLE_HEADER_PRINT_INTERVAL
# Set the flag used to check if the active fan control profile has changed
IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true

# Check present sensors
IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU2_TEMPERATURE_SENSOR_PRESENT=true
retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
if [ -z "$EXHAUST_TEMPERATURE" ]
then
  echo "No exhaust temperature sensor detected."
  IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$CPU2_TEMPERATURE" ]
then
  echo "No CPU2 temperature sensor detected."
  IS_CPU2_TEMPERATURE_SENSOR_PRESENT=false
fi
# Output new line to beautify output if one of the previous conditions have echoed
if ! $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT || ! $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
then
  echo ""
fi

# Start monitoring
while true; do
  # Sleep for the specified interval before taking another reading
  sleep $CHECK_INTERVAL &
  SLEEP_PROCESS_PID=$!

  retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT

  # Define functions to check if CPU 1, CPU 2, and GPU temperatures are above the threshold
  function CPU1_OVERHEAT () { [ $CPU1_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD ]; }
  function GPU_OVERHEAT () { [ $GPU_TEMPERATURE -gt $GPU_TEMPERATURE_THRESHOLD ]; }
  if $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
  then
    function CPU2_OVERHEAT () { [ $CPU2_TEMPERATURE -gt $CPU_TEMPERATURE_THRESHOLD ]; }
  fi

  # Initialize a variable to store the comments displayed when the fan control profile changed
  COMMENT=" -"
  # Check if CPU 1 is overheating then apply Dell default dynamic fan control profile if true

# Check combinations of overheating scenarios involving CPU1, CPU2, and GPU
  if CPU1_OVERHEAT && GPU_OVERHEAT && $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 1, CPU 2, and GPU temperatures are too high, Dell default dynamic fan control profile applied for safety"
    fi

  elif CPU1_OVERHEAT && GPU_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 1 and GPU temperatures are too high, Dell default dynamic fan control profile applied for safety"
    fi

  elif CPU1_OVERHEAT && $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 1 and CPU 2 temperatures are too high, Dell default dynamic fan control profile applied for safety"
    fi

  elif $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEAT && GPU_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 2 and GPU temperatures are too high, Dell default dynamic fan control profile applied for safety"
    fi

  elif CPU1_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 1 temperature is too high, Dell default dynamic fan control profile applied for safety"
    fi

  elif $IS_CPU2_TEMPERATURE_SENSOR_PRESENT && CPU2_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="CPU 2 temperature is too high, Dell default dynamic fan control profile applied for safety"
    fi

  elif GPU_OVERHEAT
  then
    apply_Dell_fan_control_profile
    if ! $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="GPU temperature is too high, Dell default dynamic fan control profile applied for safety"
    fi

  else
    apply_user_fan_control_profile
    # Check if user fan control profile is applied then apply it if not
    if $IS_DELL_FAN_CONTROL_PROFILE_APPLIED
    then
      IS_DELL_FAN_CONTROL_PROFILE_APPLIED=false
      COMMENT="All temperatures are within safe limits (<= threshold), user's fan control profile applied."
    fi
  fi

  # Print temperatures, active fan control profile and comment if any change happened during last time interval
#  if [ $i -eq $TABLE_HEADER_PRINT_INTERVAL ]
#  then
#    echo "                     ------- Temperatures -------"
#    echo "    Date & time      Inlet  CPU 1  CPU 2  Exhaust  GPU          Active fan speed profile          Third-party PCIe card Dell default cooling response  Comment"
#    i=0
#  fi
#  printf "%19s  %3dÂ°C  %3dÂ°C  %3sÂ°C  %5sÂ°C  %40s  %51s  %s\n" "$(date +"%d-%m-%Y %T")" "$INLET_TEMPERATURE" "$CPU1_TEMPERATURE" "$CPU2_TEMPERATURE" "$GPU_TEMPERATURE" "$EXHAUST_TEMPERATURE" "$CURRENT_FAN_CONTROL_PROFILE" "$THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS" "$COMMENT"
#  ((i++))
#  wait $SLEEP_PROCESS_PID

  # Print temperatures, active fan control profile, and comments if any change happened
  if [ $i -eq $TABLE_HEADER_PRINT_INTERVAL ]; then
    # Display a formatted header for clarity
    echo "---------------------- Temperature and Fan Control Monitoring ----------------------"
    echo "    Date & Time       Inlet Â°C   CPU 1 Â°C  CPU 2 Â°C  Exhaust Â°C  GPU Â°C    Active Profile                     PCIe Cooling   Status"
    echo "-------------------------------------------------------------------------------------"
    i=0
  fi

  # Format the output line with clear columns
  printf "%-19s  %-7s  %-7s  %-7s  %-7s  %-7s  %-35s  %-15s  %s\n" \
    "$(date +"%d-%m-%Y %T")" \
    "$INLET_TEMPERATURE" \
    "$CPU1_TEMPERATURE" \
    "$CPU2_TEMPERATURE" \
    "$EXHAUST_TEMPERATURE" \
    "$GPU_TEMPERATURE" \
    "$CURRENT_FAN_CONTROL_PROFILE" \
    "$COMMENT"

  ((i++))
  wait $SLEEP_PROCESS_PID

done
