#!/bin/bash

chown -R www-data:www-data /var/testlink
chown -R www-data:www-data /var/www/html
chmod -R 775 /var/testlink
chmod -R 775 /var/www/html/gui/templates_c

# Garante que config_db.inc.php seja gravavel pelo instalador (arquivo montado via volume do host).
# Sem isso o Docker pode montar o arquivo sem permissao de escrita para www-data e o
# instalador falha com "TestLink couldn't write the config file".
touch /var/www/html/config_db.inc.php
chown www-data:www-data /var/www/html/config_db.inc.php
chmod 664 /var/www/html/config_db.inc.php

exec "$@"
