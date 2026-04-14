#!/bin/bash

chown -R www-data:www-data /var/testlink
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/testlink
chmod -R 775 /var/www/html/gui/templates_c

exec "$@"
