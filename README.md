# Dell PowerEdge Fan Controller with NVIDIA GPU Support

Scripts to control a Dell PowerEdge server's fan speed via IPMI, with configurable thresholds for CPU and NVIDIA GPU temperatures. **Use at your own risk.**

<div id="top"></div>

---

## Console Log Example

To check the status of the fan controller service:

```bash
systemctl status dell_fan_controller
```

![Service Status](https://user-images.githubusercontent.com/37409593/216442212-d2ad7ff7-0d6f-443f-b8ac-c67b5f613b83.png)

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Prerequisites
                 

### Supported iDRAC Version

This script is compatible with Dell PowerEdge servers that support IPMI commands, specifically those with iDRAC firmware **version < 3.30.30.30**.

### Enable IPMI Over LAN (for Remote Use)

To enable IPMI over LAN (skip if using in "local" mode):

1. Log in to your iDRAC web console.

    ![Step 1](https://user-images.githubusercontent.com/37409593/210168273-7d760e47-143e-4a6e-aca7-45b483024139.png)

2. Expand "iDRAC Settings" in the left menu, select "Network," and click the "IPMI Settings" link.

    ![Step 2](https://user-images.githubusercontent.com/37409593/210168249-994f29cc-ac9e-4667-84f7-07f6d9a87522.png)

3. Check the "Enable IPMI over LAN" box, then click "Apply."
       
                       
                     
                         
                       
                       
               
   

    ![Step 3](https://user-images.githubusercontent.com/37409593/210168248-a68982c4-9fe7-40e7-8b2c-b3f06fbfee62.png)

4. Test IPMI over LAN access with:

    ```bash
    apt -y install ipmitool
    ipmitool -I lanplus \
      -H <iDRAC IP address> \
      -U <iDRAC username> \
      -P <iDRAC password> \
      sdr elist all
    ```

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Setup

1. Clone the repository:

    ```bash
    git clone https://github.com/OCT0PUSCRIME/Dell_iDRAC_fan_controller_with_NVIDIA.git /opt/Dell_iDRAC_fan_controller_with_NVIDIA
    ```
                                                                                   
   
                                             
         
   
                                         
   
                                                   
   
   
                                                                                                      
   

2. Configure the `.env` file with your iDRAC host, credentials, and fan settings:

    ```bash
    cd /opt/Dell_iDRAC_fan_controller_with_NVIDIA
    nano .env
    ```

3. Install and start the service:

    ```bash
    cp dell_fan_controller.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl start dell_fan_controller
    systemctl enable dell_fan_controller
    ```

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Parameters

All parameters are optional and have default values:

- `IDRAC_HOST`: iDRAC IP address or "local" for local control. **Default**: "local".
- `IDRAC_USERNAME`: Only needed for remote iDRAC. **Default**: "root".
- `IDRAC_PASSWORD`: Only needed for remote iDRAC. **Default**: "calvin".
- `FAN_SPEED`: Desired fan speed as a percentage (0–100) or hexadecimal (0x00–0x64). **Default**: 25%.
- `CPU_TEMPERATURE_THRESHOLD`: Maximum CPU temperature before BIOS fan mode activates. **Default**: 50°C.
- `GPU_TEMPERATURE_THRESHOLD`: Maximum GPU temperature before BIOS fan mode activates. **Default**: 75°C.
- `CHECK_INTERVAL`: Time (in seconds) between temperature checks. **Default**: 60s.

<p align="right">(<a href="#top">back to top</a>)</p>

---

## Troubleshooting

If the server frequently reverts to the default Dell fan mode:
                                                                                                                                                                                                                                                                                                                                                                                          
                                                                                                                                      
                                                                                                                                          

1. Verify the `Tcase` temperature (maximum case temperature) for your CPU on [Intel Ark](https://ark.intel.com) or a similar resource, and set `CPU_TEMPERATURE_THRESHOLD` slightly below this value.  
   *Example: For Intel Xeon E5-2630L v2, with Tcase = 63°C, set `CPU_TEMPERATURE_THRESHOLD` to 60°C.*

2. If the threshold is correctly set, increase the `FAN_SPEED` to improve airflow and reduce temperatures.

3. If increasing fan speed doesn’t resolve the issue, consider reapplying thermal paste on your CPU.

<p align="right">(<a href="#top">back to top</a>)</p>

---
               

## Contributing

Contributions are welcome to improve this project. To contribute:
                                                      

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Any feedback or suggestions can also be submitted as issues.

<p align="right">(<a href="#top">back to top</a>)</p>
