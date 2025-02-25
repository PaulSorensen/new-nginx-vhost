#!/bin/bash
################################################################################
#  Script Name : New Nginx vHost
#  Author      : Paul Sørensen
#  Website     : https://paulsorensen.io
#  GitHub      : https://github.com/paulsorensen
#  Version     : 1.0
#  Last Update : 25.02.2025
#
#  Description:
#  Sets up a new vHost on Nginx with SSL certificate and proper configuration.
#  Website Root will be set up in: /var/www/domain.com/wwwroot/
#  Logs will be located in: /var/www/domain.com/logs/
#
#  Supported index files:
#  index.php index.html index.htm default.cshtml default.aspx default.asp
#
#  Usage:
#  ./new-nginx-vhost.sh domain.com
#
#  Remember to define your email in the variable below for Cerbot notificatoins.
#
#  If you found this script useful, a small tip is appreciated ❤️
#  https://buymeacoffee.com/paulsorensen
################################################################################

# Exit immediately if a command exits with a non-zero status
set -e

# Define email for Certbot notifications
EMAIL="ex4mple@dom4in.com"

BLUE='\033[1;34m'
NC='\033[0m'
echo -e "${BLUE}New Nginx vHost by paulsorensen.io${NC}"
echo ""

# Check if domain is provided
DOMAIN=$1
if [ -z "$DOMAIN" ]; then
    echo "Usage: $0 domain.com"
    exit 1
fi

################################################################################
#  1. Set up directories
################################################################################
echo "Creating vHost directories..."
sudo mkdir -p /var/www/$DOMAIN/wwwroot
sudo mkdir -p /var/www/$DOMAIN/logs
# Create the ACME challenge directory
sudo mkdir -p /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge
sudo chown -R www-data:www-data /var/www/$DOMAIN
sudo chmod -R 750 /var/www/$DOMAIN

################################################################################
#  2. Temporary HTTP-Only Nginx Configuration (used for Certbot)
################################################################################
echo "Creating temporary HTTP-only Nginx configuration..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;

    root /var/www/$DOMAIN/wwwroot;
    index index.php index.html index.htm default.cshtml default.aspx default.asp;

    # Minimal location block for direct file checks
    location / {
        try_files \$uri \$uri/ =404;
    }

    # Standard files
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log error;

    # PHP Processing Block
    location ~ \.php$ {
        add_header X-Powered-By "Interscion.com";
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

    # ACME Challenge Location
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge/;
        default_type "text/plain";
        try_files \$uri =404;
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
EOL

################################################################################
#  3. Enable the Temporary HTTP-Only Site
################################################################################
echo "Enabling temporary site..."
if [ -L "/etc/nginx/sites-enabled/$DOMAIN" ]; then
    echo "Removing existing symlink for $DOMAIN..."
    sudo rm -f "/etc/nginx/sites-enabled/$DOMAIN"
fi
sudo ln -s /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

################################################################################
#  4. Start or Reload Nginx
################################################################################
echo "Starting Nginx (if not running)..."
if ! sudo systemctl is-active --quiet nginx; then
    sudo systemctl start nginx
else
    sudo systemctl reload nginx
fi

################################################################################
#  5. Generate SSL Certificate with Certbot
################################################################################
echo "Generating SSL certificate with Certbot..."
if ! sudo certbot certonly --webroot -w /var/www/$DOMAIN/wwwroot --agree-tos --no-eff-email --email "$EMAIL" -d $DOMAIN -d www.$DOMAIN; then
    echo "Certbot failed. Check /var/log/letsencrypt/letsencrypt.log for details."
    exit 1
fi

################################################################################
#  6. Final Nginx Configuration (HTTP -> HTTPS Redirect + Generic Rewrite)
################################################################################
echo "Creating final Nginx configuration with SSL..."
sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOL
# HTTP Server: Serve ACME challenge and redirect other traffic to HTTPS
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;

    # Serve ACME challenge without redirection
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge/;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS Server: Generic rewrite (suitable for WordPress and static sites)
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $DOMAIN www.$DOMAIN;

    root /var/www/$DOMAIN/wwwroot;
    index index.php index.html index.htm default.cshtml default.aspx default.asp;

    client_max_body_size 256M;

    # Generic rewrite: if file or directory not found, fallback to index.php
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log /var/www/$DOMAIN/logs/access.log;
    error_log /var/www/$DOMAIN/logs/error.log error;

    # PHP Processing Block
    location ~ \.php$ {
        add_header X-Powered-By "Interscion.com";
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

    # ACME Challenge Location
    location ^~ /.well-known/acme-challenge/ {
        alias /var/www/$DOMAIN/wwwroot/.well-known/acme-challenge/;
        default_type "text/plain";
        try_files \$uri =404;
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
#  7. Reload Nginx with the Final Configuration
################################################################################
echo "Finalizing Nginx configuration with SSL..."
if ! sudo systemctl is-active --quiet nginx; then
    sudo systemctl start nginx
else
    sudo systemctl reload nginx
fi

################################################################################
#  8. Create a default index.php
################################################################################
echo "Creating index.php..."
sudo tee /var/www/$DOMAIN/wwwroot/index.php > /dev/null <<EOL
<h1><?php echo "Welcome to ", \$_SERVER['HTTP_HOST']; ?></h1>
EOL

# Set correct permissions
sudo chown www-data:www-data /var/www/$DOMAIN/wwwroot/index.php
sudo chmod 644 /var/www/$DOMAIN/wwwroot/index.php

echo -e "${BLUE}Deployment completed! $DOMAIN is live with SSL and generic configuration.${NC}"