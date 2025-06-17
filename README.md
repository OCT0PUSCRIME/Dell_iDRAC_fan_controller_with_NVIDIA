# Dell PowerEdge Tiered Fan Controller with NVIDIA GPU Support

Scripts to dynamically control a Dell PowerEdge server's fan speed via IPMI, featuring a configurable tiered system based on CPU and NVIDIA GPU temperatures for smoother and quieter operation. **Use at your own risk.**

<div id="top"></div>

---

## Overview

This project provides a set of Bash scripts (`Dell_iDRAC_fan_controller_tiered.sh` and `functions_tiered.sh`) that allow for fine-grained control over your Dell PowerEdge server's cooling fans. Instead of a simple on/off approach, it implements a multi-tier system where fan speeds gradually increase based on configurable temperature thresholds for both CPUs and NVIDIA GPUs. This helps in maintaining optimal temperatures while minimizing fan noise, especially during fluctuating workloads.

Key features include:
-   **Tiered Fan Control:** Define multiple fan speed levels, each triggered by specific CPU and GPU temperature thresholds.
-   **Hysteresis:** Prevents rapid fan speed changes ("flapping") when temperatures hover around a threshold.
-   **NVIDIA GPU Temperature Monitoring:** Directly incorporates GPU temperatures into the fan control logic.
-   **Configurable Logging:** Choose between detailed periodic status updates or a quieter mode that only logs significant events (e.g., fan changes, critical temperature alerts).
-   **Safety Fallback:** Automatically reverts to Dell's default dynamic fan control if critical temperature limits are breached.
-   **Local or Remote iDRAC Control:** Works with local IPMI access or remote iDRAC connections.

## Console Log / Service Status

To check the status of the fan controller service (assuming you've named your service `dell_fan_controller`):

```bash
systemctl status dell_fan_controller
```

![Service Status](https://user-images.githubusercontent.com/37409593/216442212-d2ad7ff7-0d6f-443f-b8ac-c67b5f613b83.png)

The script itself also provides event-driven logging. If `SCRIPT_VERBOSITY=quiet` (recommended for systemd services), it will log important events like fan tier changes or critical temperature alerts to its standard output/error, which systemd will capture.

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Prerequisites

### Supported Hardware & Software
* **Dell PowerEdge Servers:** Compatible with servers supporting standard IPMI commands for fan control.
* **iDRAC:** An iDRAC module is required. The original script mentioned compatibility with iDRAC firmware **version < 3.30.30.30**. While newer versions may work for basic IPMI commands, this specific compatibility note is retained from the original source.
* **NVIDIA GPU (Optional but Recommended):** For GPU temperature monitoring, an NVIDIA GPU and the `nvidia-smi` command-line utility are required. If no NVIDIA GPU is present or `nvidia-smi` is unavailable, GPU temperature readings will be skipped or marked as N/A.
* **`ipmitool`:** This command-line utility must be installed to interact with the iDRAC.
    ```bash
    sudo apt update && sudo apt -y install ipmitool
    ```
* **`bc`:** The Basic Calculator utility is used for floating-point comparisons in temperature checks. It's usually installed by default on most Linux distributions.
    ```bash
    sudo apt -y install bc # If not already present
    ```

### Enable IPMI Over LAN (for Remote Use)

To enable IPMI over LAN (skip if using the script in "local" mode via `/dev/ipmi0`):

1.  Log in to your iDRAC web console.
    ![Step 1](https://user-images.githubusercontent.com/37409593/210168273-7d760e47-143e-4a6e-aca7-45b483024139.png)
2.  Navigate to "iDRAC Settings" -> "Network," and click the "IPMI Settings" tab/link.
    ![Step 2](https://user-images.githubusercontent.com/37409593/210168249-994f29cc-ac9e-4667-84f7-07f6d9a87522.png)
3.  Check the "Enable IPMI over LAN" box, then click "Apply."
    ![Step 3](https://user-images.githubusercontent.com/37409593/210168248-a68982c4-9fe7-40e7-8b2c-b3f06fbfee62.png)
4.  Test IPMI over LAN access from the machine where the script will run:
    ```bash
    ipmitool -I lanplus \
      -H <iDRAC_IP_address> \
      -U <iDRAC_username> \
      -P <iDRAC_password> \
      sdr type temperature
    ```
    (Replace placeholders with your iDRAC's details.)

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Setup

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/OCT0PUSCRIME/Dell_iDRAC_fan_controller_with_NVIDIA.git](https://github.com/OCT0PUSCRIME/Dell_iDRAC_fan_controller_with_NVIDIA.git) /opt/Dell_iDRAC_fan_controller_with_NVIDIA
    ```
    (Adjust the path `/opt/Dell_iDRAC_fan_controller_with_NVIDIA` as needed.)

2.  **Navigate to the script directory:**
    ```bash
    cd /opt/Dell_iDRAC_fan_controller_with_NVIDIA
    ```

3.  **Configure the `.env` file:**
    Copy the example `env.example` to `.env` (if provided) or create a new `.env` file.
    ```bash
    cp env.example .env # If env.example exists
    nano .env
    ```
    Edit `.env` to set your iDRAC connection details, temperature thresholds, fan speeds for each tier, and other operational parameters. See the "Parameters" section below for details.

4.  **Make scripts executable:**
    ```bash
    chmod +x Dell_iDRAC_fan_controller_tiered.sh functions_tiered.sh
    ```

5.  **Install and start the systemd service:**
    (Ensure the `ExecStart` path in `dell_fan_controller.service` points to `Dell_iDRAC_fan_controller_tiered.sh` in your chosen directory.)
    ```bash
    sudo cp dell_fan_controller.service /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl start dell_fan_controller.service
    sudo systemctl enable dell_fan_controller.service
    ```

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Parameters (`.env` File Configuration)

All parameters are configured in the `.env` file. Default values are provided in the script if not set in `.env`.

### iDRAC Connection
-   `IDRAC_HOST`: iDRAC IP address or hostname. Set to `"local"` for local IPMI access via `/dev/ipmi0`.
    * **Default**: `"local"`
-   `IDRAC_USERNAME`: Username for remote iDRAC access. Not used if `IDRAC_HOST` is "local".
    * **Default**: (none, script will exit if required and not set)
-   `IDRAC_PASSWORD`: Password for remote iDRAC access. Not used if `IDRAC_HOST` is "local".
    * **Default**: (none, script will exit if required and not set)

### Tiered Temperature Thresholds (°C)
Define the *upper temperature limit* for each tier. If a component's temperature exceeds its `*_TEMP_THRESHOLD_TIERX`, the script will consider moving to Tier X+1 fan speed. If any component exceeds its `*_TEMP_THRESHOLD_TIER4`, the script reverts to Dell's default dynamic fan control for safety.

-   `CPU_TEMP_THRESHOLD_TIER1`: **Default**: `50`
-   `CPU_TEMP_THRESHOLD_TIER2`: **Default**: `60`
-   `CPU_TEMP_THRESHOLD_TIER3`: **Default**: `70`
-   `CPU_TEMP_THRESHOLD_TIER4`: **Default**: `78` (Critical safety threshold)

-   `GPU_TEMP_THRESHOLD_TIER1`: **Default**: `48`
-   `GPU_TEMP_THRESHOLD_TIER2`: **Default**: `58`
-   `GPU_TEMP_THRESHOLD_TIER3`: **Default**: `68`
-   `GPU_TEMP_THRESHOLD_TIER4`: **Default**: `76` (Critical safety threshold for GPU)

### Tiered Fan Speeds (%)
Define the fan speed percentage (0-100) for each corresponding tier.

-   `FAN_SPEED_TIER1`: **Default**: `12`
-   `FAN_SPEED_TIER2`: **Default**: `22`
-   `FAN_SPEED_TIER3`: **Default**: `38`
-   `FAN_SPEED_TIER4`: **Default**: `55`

### Script Operation
-   `CHECK_INTERVAL`: Time (in seconds) between temperature checks and potential fan adjustments.
    * **Default**: `10`
-   `HYSTERESIS_TEMP`: Temperature (in °C) used for hysteresis. To slow fans down (move to a lower tier), component temperatures must drop below the previous tier's threshold *minus* this hysteresis value. This prevents rapid fan speed changes.
    * **Default**: `3`
-   `SCRIPT_VERBOSITY`: Controls logging behavior.
    * `"normal"`: Prints a full status table periodically.
    * `"quiet"`: Suppresses the periodic table, only logging critical events, errors, and actual fan speed/tier changes. Recommended for systemd services to reduce syslog noise.
    * **Default**: `"normal"`
-   `FORCE_DELL_CHECK_SKIP`: Set to `"true"` to bypass the Dell server model check if the `ipmitool fru` command fails to retrieve manufacturer information. Use with caution.
    * **Default**: `"false"`

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Troubleshooting

* **Fans Reverting to Dell Default / High Speeds:**
    * Your `*_TEMP_THRESHOLD_TIER4` for CPU or GPU is being breached.
    * **Solution:**
        1.  Consider increasing the `FAN_SPEED_TIER4` (and possibly `FAN_SPEED_TIER3`) to provide more cooling before hitting the critical threshold.
        2.  If temperatures are still too high, you may need to allow a higher critical threshold by increasing `*_TEMP_THRESHOLD_TIER4`, but ensure this is within safe operating limits for your hardware.
        3.  Verify thermal paste application and heatsink mounting for CPUs or other components if temperatures are unexpectedly high.

* **Fans "Flapping" or Rapidly Changing Speed:**
    * Temperatures are hovering very close to a tier threshold.
    * **Solution:**
        1.  Increase `HYSTERESIS_TEMP` in your `.env` file (e.g., from `3` to `4` or `5`). This makes the script less eager to reduce fan speed.
        2.  Ensure there are reasonable temperature gaps between your defined `*_TEMP_THRESHOLD_TIERX` values.

* **"Failed to retrieve FRU data" or "Server isn't a Dell product" Errors:**
    * The script uses `ipmitool fru` to verify the server is a Dell product. This command can sometimes fail or be unavailable.
    * **Solution:**
        1.  Ensure `ipmitool` is working correctly and can communicate with your iDRAC. Test the `ipmitool ... fru` command manually.
        2.  If you are certain your server is a Dell PowerEdge and the script should run, you can set `FORCE_DELL_CHECK_SKIP=true` in your `.env` file to bypass this check.

* **Script Not Changing Fan Speeds:**
    * Check iDRAC logs for any IPMI command errors.
    * Ensure `IDRAC_HOST` and credentials (if remote) are correct.
    * Verify `ipmitool` commands work manually from the command line using the same parameters the script would use (e.g., `ipmitool -I open raw 0x30 0x30 0x01 0x00` for local access to disable dynamic control).

* **High Syslog Noise (if `SCRIPT_VERBOSITY=normal`):**
    * Set `SCRIPT_VERBOSITY=quiet` in your `.env` file.
    * Alternatively, configure your systemd service file to redirect the script's `StandardOutput` and `StandardError` to a dedicated log file instead of the journal/syslog.

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Contributing

Contributions are welcome to improve this project. To contribute:

1.  Fork the Project
2.  Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the Branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

Any feedback or suggestions can also be submitted as issues on the GitHub repository.

<p align="right">(<a href="#top">back to top</a>)</p>

---

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/oct0puscrime)
