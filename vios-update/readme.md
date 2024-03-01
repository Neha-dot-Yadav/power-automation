# VIOS Update Automation
VIOS stands for Virtual I/O Server, which is a component of IBM's PowerVM virtualization technology for IBM Power Systems.
VIOS update refers to the process of updating or upgrading the Virtual I/O Server software to a newer version or applying patches and fixes to existing installations. These updates typically include bug fixes, security patches, performance improvements, and new features introduced by IBM.

## Resources
The ``` vios_update.sh ``` script automates the VIOS Update steps mentioned in the official release [docs](https://www.ibm.com/support/pages/vios-31431-fix-pack-release-notes-1)

## How to run the script
The script can be triggered from any environment which supports Bash, by running the following command:
```bash 
vios_update.sh  --remote-host <vios_ip> --remote-user <vios_username> --remote-password <vios_password> --sftp-doamin <sftp_host> --sftp-user <sftp_username> --sftp-password <sftp_password> --vios-fix <vios_version>```
