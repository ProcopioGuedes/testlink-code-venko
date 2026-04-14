FROM php:7.3-apache

RUN apt-get update && apt-get install -y \
    wget unzip \
    libpng-dev libjpeg-dev libfreetype6-dev \
    libzip-dev libxml2-dev libcurl4-openssl-dev \
    mariadb-client \
    && docker-php-ext-install mysqli gd zip mbstring xml curl \
    && a2enmod rewrite

WORKDIR /var/www/html

RUN wget https://github.com/TestLinkOpenSourceTRMS/testlink-code/archive/refs/tags/1.9.20.tar.gz \
    && tar -xzf 1.9.20.tar.gz \
    && mv testlink-code-1.9.20/* . \
    && rm -rf testlink-code-1.9.20* \
    && mkdir -p /var/testlink/logs /var/testlink/upload_area gui/templates_c config_db

RUN echo "max_execution_time=120" >> /usr/local/etc/php/php.ini \
 && echo "memory_limit=256M" >> /usr/local/etc/php/php.ini

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
