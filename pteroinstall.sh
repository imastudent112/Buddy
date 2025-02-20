#!/bin/bash

# Prompt for input values
read -p "Enter your domain (e.g., example.com): " dm
read -sp "Enter the MariaDB password for the 'pterodactyl' user: " PPWD
echo  # Just to move to a new line after password input
read -p "Enter your timezone (e.g., America/New_York): " TZ
read -sp "Enter the password for the Pterodactyl admin user: " pw
echo  # Just to move to a new line after password input

# Update system and install necessary dependencies
echo "Updating system and installing dependencies..."
sudo apt update && sudo apt -y upgrade
sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg \
    certbot python3-certbot-nginx \
    php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
    mariadb-server nginx tar unzip git redis-server

# Install Composer (for PHP dependencies)
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Download and extract the Pterodactyl panel
echo "Downloading and extracting Pterodactyl panel..."
mkdir -p /var/www/pterodactyl && cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz && chmod -R 755 storage/* bootstrap/cache/

# Database Setup for Pterodactyl
echo "Setting up MySQL database for Pterodactyl..."
mysql -u root -p"$PPWD" -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$PPWD';"
mysql -u root -p"$PPWD" -e "CREATE DATABASE panel;"
mysql -u root -p"$PPWD" -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"

# Pterodactyl installation steps
echo "Running Pterodactyl setup..."
cp .env.example .env
COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
php artisan key:generate --force
php artisan p:environment:setup
php artisan p:environment:database
php artisan p:environment:mail

# MySQL setup for Pterodactyl
php artisan migrate --seed --force
php artisan p:user:make

# Set permissions for Pterodactyl files
echo "Setting permissions for Pterodactyl files..."
chown -R www-data:www-data /var/www/pterodactyl/*

# Set up CRON job for Pterodactyl
echo "Setting up cron job for Pterodactyl..."
(crontab -l ; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

# Set up Pterodactyl Queue Worker
echo "Setting up Pterodactyl Queue Worker..."
echo -e "[Unit]\nDescription=Pterodactyl Queue Worker\nAfter=redis-server.service\n\n[Service]\nUser=www-data\nGroup=www-data\nRestart=always\nExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3\nStartLimitInterval=180\nStartLimitBurst=30\nRestartSec=5s\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/pteroq.service
sudo systemctl daemon-reload
sudo systemctl enable --now pteroq.service

# Nginx Configuration for Pterodactyl
echo "Configuring Nginx for Pterodactyl..."
rm /etc/nginx/sites-enabled/default
echo -e "server {\n    listen 80;\n    server_name $dm;\n    return 301 https://\$server_name$request_uri;\n}\n\nserver {\n    listen 443 ssl http2;\n    server_name $dm;\n\n    root /var/www/pterodactyl/public;\n    index index.php;\n\n    access_log /var/log/nginx/pterodactyl.app-access.log;\n    error_log  /var/log/nginx/pterodactyl.app-error.log error;\n\n    client_max_body_size 100m;\n    client_body_timeout 120s;\n\n    sendfile off;\n\n    ssl_certificate /etc/letsencrypt/live/$dm/fullchain.pem;\n    ssl_certificate_key /etc/letsencrypt/live/$dm/privkey.pem;\n    ssl_session_cache shared:SSL:10m;\n    ssl_protocols TLSv1.2 TLSv1.3;\n    ssl_ciphers \"ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384\";\n    ssl_prefer_server_ciphers on;\n\n    add_header X-Content-Type-Options nosniff;\n    add_header X-XSS-Protection \"1; mode=block\";\n    add_header X-Robots-Tag none;\n    add_header Content-Security-Policy \"frame-ancestors 'self'\";\n    add_header X-Frame-Options DENY;\n    add_header Referrer-Policy same-origin;\n\n    location / {\n        try_files \$uri \$uri/ /index.php?\$query_string;\n    }\n\n    location ~ \\.php$ {\n        fastcgi_split_path_info ^(.+\\.php)(/.+)$;\n        fastcgi_pass unix:/run/php/php8.3-fpm.sock;\n        fastcgi_index index.php;\n        include fastcgi_params;\n        fastcgi_param PHP_VALUE \"upload_max_filesize = 100M \\n post_max_size=100M\";\n        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;\n    }\n\n    location ~ /\.ht {\n        deny all;\n    }\n}" > /etc/nginx/sites-available/pterodactyl.conf

sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
sudo systemctl restart nginx

# Certbot SSL setup (Let's Encrypt)
echo "Setting up SSL with Certbot..."
sudo certbot --nginx -d $dm --agree-tos --non-interactive --email your-email@example.com

# Final message
echo "Pterodactyl installation completed successfully! Access it at https://$dm"
