# New Nginx vHost

## Overview
**New Nginx vHost** is a Bash script that automates the creation and configuration of a new Nginx virtual host. It sets up a secure web server with SSL, proper directory structures, and necessary permissions.

## Features
- Creates a new Nginx vHost configuration.
- Sets up directories for web files and logs.
- Generates an SSL certificate using Certbot (Let's Encrypt).
- Supports both Cloudflare Flexible and Strict (Full).
- Configures HTTP to HTTPS redirection.
- Configures www to non-www redirection.
- Supports multiple index file types.
- Configures PHP-FPM 8.3.
- Ensures secure permissions and ownership.

## Requirements
Before running the script, ensure that:
- The domain’s **DNS records are correctly pointing to the server** and are not proxied (Cloudflare). You can enable proxy after the vHost is created.
- **Nginx** is installed and running.
- **Certbot** (Let's Encrypt) is installed for SSL certificate generation.
- **PHP-FPM** is installed if PHP support is needed.
- The script uses **PHP 8.3** by default. Modify the PHP-FPM socket in the script if using a different version.
- You have `sudo` privileges.

## Usage
Run the script with the domain as an argument:

```bash
./new-nginx-vhost.sh domain.com
```

## Configuration
During execution, the script:
- Creates the necessary vHost directories:
  - **Website Root:** `/var/www/domain.com/wwwroot/`
  - **Log Folder:** `/var/www/domain.com/logs/`
- Sets up a **temporary HTTP-only** Nginx configuration to allow Certbot to verify the domain.
- Requests an SSL certificate using **Certbot**.
- Replaces the temporary Nginx configuration with a **final secure version** supporting HTTPS and proper PHP handling.
- Asks you to enter an email address for Certbot notifications.
- Asks for an 'X-Powered-By' header. If you don't know what that is, leave it empty to completely remove it, or set it to 'Coffee'.

## Important Notes
- This script implements the ACME Challenge method for SSL certificate issuance and renewal using Certbot. By configuring the .well-known/acme-challenge/ directory within the Nginx virtual host, Certbot can automatically verify domain ownership over HTTP (port 80). This means users do not need to set up DNS-based challenges for SSL renewal.

However, automatic renewal is not configured by this script. To ensure certificates remain valid, users must manually set up a cron job or systemd timer to run:
```bash
sudo certbot renew --quiet
```
It is recommended to schedule this command to run at least twice per day to allow Certbot to handle retries in case of temporary failures.

## Enjoying This Script?
**If you found this script useful, a small tip is appreciated ❤️**
[https://buymeacoffee.com/paulsorensen](https://buymeacoffee.com/paulsorensen)

## License
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the License.

**Legal Notice:** If you edit and redistribute this code, you must mention the original author, **Paul Sørensen** ([paulsorensen.io](https://paulsorensen.io)), in the redistributed code or documentation.

**Copyright (C) 2025 Paul Sørensen ([paulsorensen.io](https://paulsorensen.io))**

See the LICENSE file in this repository for the full text of the GNU General Public License v3.0, or visit [https://www.gnu.org/licenses/gpl-3.0.txt](https://www.gnu.org/licenses/gpl-3.0.txt).