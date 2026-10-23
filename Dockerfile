# syntax=docker/dockerfile:1
#
# ResourceSpace Docker image
#
# Based on the packaging of the official repository github.com/resourcespace/docker,
# extended with environment-based configuration, an automatic first-time install,
# automatic restore from a database dump and scheduled database dumps.

ARG UBUNTU_VERSION=24.04

# -----------------------------------------------------------------------------
# Stage "source": ResourceSpace code from the official SVN release branch
# -----------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION} AS source

ARG RS_RELEASE=11.0
ARG RS_REVISION=HEAD

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates subversion composer php-cli unzip; \
    svn export -q -r "${RS_REVISION}" \
      "https://svn.resourcespace.com/svn/rs/releases/${RS_RELEASE}" /rs; \
    # Install PHP dependencies only if the release does not ship them
    if [ -f /rs/composer.json ] && [ ! -f /rs/vendor/autoload.php ]; then \
      composer install --working-dir=/rs --no-dev --no-interaction --no-progress \
        --ignore-platform-reqs --optimize-autoloader; \
    fi; \
    rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Final image
# -----------------------------------------------------------------------------
FROM ubuntu:${UBUNTU_VERSION}

ARG RS_RELEASE=11.0
ARG RS_REVISION=HEAD

ENV DEBIAN_FRONTEND=noninteractive \
    RS_RELEASE=${RS_RELEASE} \
    RS_REVISION=${RS_REVISION}

# Same runtime packages as the official image, minus build tools (php-dev,
# python3-pip), subversion, postfix and OpenCV (facial recognition is
# deprecated upstream). Added: mariadb-client for dumps/restore, curl for the
# healthcheck, php-xml.
RUN set -eux; \
    apt-get update; \
    apt-get install -y \
      apache2 \
      libapache2-mod-php \
      php \
      php-apcu \
      php-curl \
      php-gd \
      php-intl \
      php-mbstring \
      php-mysqlnd \
      php-xml \
      php-zip \
      imagemagick \
      ghostscript \
      antiword \
      poppler-utils \
      libimage-exiftool-perl \
      ffmpeg \
      cron \
      mariadb-client \
      curl \
      ca-certificates \
      nano; \
    rm -rf /var/lib/apt/lists/*; \
    a2enmod remoteip headers; \
    rm -f /etc/cron.daily/* /var/www/html/index.html

COPY --from=source /rs /var/www/html
COPY rootfs/ /

RUN set -eux; \
    chmod 0755 /usr/local/bin/*; \
    a2enconf resourcespace; \
    # Media files live in the data volume, outside the web root.
    # /var/www/html/filestore only points there so that URLs keep working.
    rm -rf /var/www/html/filestore; \
    ln -s /data/filestore /var/www/html/filestore; \
    # Generated at start from environment variables
    rm -f /var/www/html/include/config.php; \
    chown -R root:root /var/www/html; \
    php -l /usr/local/lib/resourcespace/setup.php; \
    php -l /usr/local/lib/resourcespace/write-config.php

VOLUME ["/data"]
WORKDIR /var/www/html
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=10s --start-period=5m --retries=5 \
  CMD curl -fsS -o /dev/null http://localhost/login.php || exit 1

ENTRYPOINT ["/usr/local/bin/rs-entrypoint"]
