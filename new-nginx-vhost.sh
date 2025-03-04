#!/bin/bash
################################################################################
#  Script Name : New Nginx vHost
#  Author      : Paul Sørensen
#  Website     : https://paulsorensen.io
#  GitHub      : https://github.com/paulsorensen
#  Version     : 1.0
#  Last Update : 04.03.2025
#
#  Description:
#  Sets up a new vHost on Nginx with SSL certificate and proper configuration.
#  Website Root will be set up in: /var/www/domain.com/wwwroot/
#  Logs will be located in: /var/www/domain.com/logs/
#
#  Usage:
#  ./new-nginx-vhost.sh domain.com
#
#  If you found this script useful, a small tip is appreciated ❤️
#  https://buymeacoffee.com/paulsorensen
################################################################################

set -e

BLUE='\033[38;5;81m'
NC='\033[0m'
echo -e "${BLUE}New Nginx vHost by paulsorensen.io${NC}"
echo ""

# Check if domain is provided
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 domain.com"
    exit 1
fi

# Prompt user for email address (required)
read -p "Please specify email address for Certbot notifications: " EMAIL
if [ -z "$EMAIL" ]; then
    echo "Error: Email is required for Certbot notifications."
    exit 1
fi

# Prompt user for 'X-Powered-By' header (optional)
read -p "Please specify 'X-Powered-By' header or leave empty to completely remove header: " POWERED_BY

################################################################################
#  1. Set up directories
################################################################################
echo "Creating vHost directories..."
sudo mkdir -p /var/www/$DOMAIN/wwwroot
sudo mkdir -p /var/www/$DOMAIN/logs
sudo mkdir -p /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge
sudo chown -R www-data:www-data /var/www/$DOMAIN
sudo chmod -R 750 /var/www/$DOMAIN

################################################################################
#  2. Temporary HTTP-Only Nginx Configuration (used for Certbot)
################################################################################
echo "Creating temporary HTTP-only Nginx configuration..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
# HTTP Server: Serve ACME challenge only for Certbot
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;
    root /var/www/$DOMAIN/wwwroot;

    # Serve ACME challenge without redirection
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge/;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # Return 404 for everything else during Certbot phase
    location / {
        try_files \$uri \$uri/ =404;
    }

    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log error;
}
EOL

################################################################################
#  3. Enable the Temporary HTTP-Only Site
################################################################################
echo "Enabling temporary site..."
if [ -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
    sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
fi
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

echo "Starting or reloading Nginx..."
if ! sudo systemctl is-active --quiet nginx; then
    sudo systemctl start nginx
else
    sudo systemctl reload nginx
fi

################################################################################
#  4. Generate SSL Certificate with Certbot
################################################################################
echo "Generating SSL certificate with Certbot..."
if ! sudo certbot certonly --webroot -w /var/www/$DOMAIN/wwwroot --agree-tos --no-eff-email --email "$EMAIL" -d $DOMAIN -d www.$DOMAIN; then
    echo "Certbot failed. Check /var/log/letsencrypt/letsencrypt.log for details."
    exit 1
fi

################################################################################
#  5. Final Nginx Configuration (HTTPS with HTTP fallback)
################################################################################
echo "Creating final Nginx configuration with SSL..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
# HTTP Server
# Serve ACME challenge, Cloudflare Flexible, and redirect to HTTPS for non-Cloudflare.
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;
    root /var/www/$DOMAIN/wwwroot;
    index index.php index.html index.htm default.cshtml default.aspx default.asp;
    client_max_body_size 256M;

    # Serve ACME challenge without redirection
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge/;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # Redirect www to non-www
    location / {
        if (\$host = www.$DOMAIN) {
            return 301 https://$DOMAIN\$request_uri;
        }
        # Redirect to HTTPS if not proxied by Cloudflare Flexible
        if (\$http_x_forwarded_proto != "https") {
            return 301 https://$DOMAIN\$request_uri;
        }
        # Else if Cloudflare Flexible
        # Serve content or fall back to index.php if file/directory not found
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log error;

    # PHP Processing Block
    location ~ \.php$ {
EOL

if [ -n "$POWERED_BY" ]; then
    echo "        add_header X-Powered-By \"$POWERED_BY\";" | sudo tee -a /etc/nginx/sites-available/$DOMAIN > /dev/null
fi

sudo tee -a /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 600;
        fastcgi_send_timeout 600;
        fastcgi_read_timeout 600;
    }

    # Security: Deny hidden files
    location ~ /\.(ht|git) {
        deny all;
    }
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
        return 444;
    }
}

# HTTPS Server
# Serve direct HTTPS requests, including Cloudflare Full (Strict).
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $DOMAIN www.$DOMAIN;
    root /var/www/$DOMAIN/wwwroot;
    index index.php index.html index.htm default.cshtml default.aspx default.asp;
    client_max_body_size 256M;

    # Serve ACME challenge without redirection
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge/;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # Redirect www to non-www
    if (\$host = www.$DOMAIN) {
        return 301 https://$DOMAIN\$request_uri;
    }

    # Serve content or fall back to index.php if file/directory not found
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log error;

    # PHP Processing Block
    location ~ \.php$ {
EOL

if [ -n "$POWERED_BY" ]; then
    echo "        add_header X-Powered-By \"$POWERED_BY\";" | sudo tee -a /etc/nginx/sites-available/$DOMAIN > /dev/null
fi

sudo tee -a /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
        fastcgi_pass unix:/var/run/php/php8.3-fpm.sock;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 600;
        fastcgi_send_timeout 600;
        fastcgi_read_timeout 600;
    }

    # Security: Deny hidden files
    location ~ /\.(ht|git) {
        deny all;
    }
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
        return 444;
    }

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
}
EOL

################################################################################
#  6. Create a default index.php
################################################################################
echo "Creating index.php..."
sudo tee /var/www/$DOMAIN/wwwroot/index.php > /dev/null <<EOL
<?php echo "<h1>Welcome to " . \$_SERVER['HTTP_HOST'] . "</h1>"; ?>
EOL

# Set correct permissions
sudo chown www-data:www-data /var/www/$DOMAIN/wwwroot/index.php
sudo chmod 644 /var/www/$DOMAIN/wwwroot/index.php

################################################################################
#  7. Reload Nginx with the Final Configuration
################################################################################
echo "Reloading Nginx with final SSL configuration..."
sudo systemctl reload nginx

echo -e "${BLUE}Deployment completed! $DOMAIN is live with SSL.${NC}"