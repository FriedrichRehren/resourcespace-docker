<div align="center">
  <h1><code>ResourceSpace</code> Docker Image</h1>
  <p>Ready-to-use container image for the open-source digital asset management system <a href="https://www.resourcespace.com">ResourceSpace</a> – configured entirely through environment variables, no web installer.</p>
  <p>
    <a href="https://github.com/FriedrichRehren/resourcespace-docker/actions/workflows/check-upstream.yml"><img alt="Check Upstream Release" src="https://github.com/FriedrichRehren/resourcespace-docker/actions/workflows/check-upstream.yml/badge.svg?branch=main"></a>
  </p>
  <p>
    <a href="https://hub.docker.com/r/friedrichrehren/resourcespace/tags"><img alt="Current Version" src="https://img.shields.io/docker/v/friedrichrehren/resourcespace?sort=date&label=Current%20Version"></a>
    <a href="https://hub.docker.com/r/friedrichrehren/resourcespace"><img alt="Docker Hub Pulls" src="https://img.shields.io/docker/pulls/friedrichrehren/resourcespace?label=Docker%20Hub%20pulls&logo=docker&logoColor=white"></a>
  </p>
</div>

## Features

| Feature | Details |
| --- | --- |
| Official code | ResourceSpace from the official SVN release branch (`releases/<version>`) |
| No web installer | `include/config.php` is generated from environment variables at every start |
| Automatic first install | empty database → tables, default data and super admin are created |
| Automatic restore | empty database + existing dump in `/data/db-dump` → dump is imported |
| Database dumps | `mariadb-dump` every 6 hours to `/data/db-dump/resourcespace.sql.gz` |
| One data volume | media, dumps and local config live in `/data`, outside the web root |
| Reverse proxy ready | honours `X-Forwarded-Proto` (secure cookies) and `X-Forwarded-For` |
| Hardened filestore | no PHP execution and no directory listings inside the filestore (except `filestore/plugins/`) |
| Tested before release | every image is installed, logged into and restored in CI before it is pushed |
| `linux/amd64` and `linux/arm64` | multi-architecture images |

## Published Images

| Registry | Image |
| --- | --- |
| Docker Hub | [`friedrichrehren/resourcespace`](https://hub.docker.com/r/friedrichrehren/resourcespace) |
| GHCR | [`ghcr.io/friedrichrehren/resourcespace`](https://github.com/users/friedrichrehren/packages/container/package/resourcespace) |

| Tag | Meaning |
| --- | --- |
| `latest` | newest revision of the newest release branch |
| `11.0` | newest revision of the `11.0` release branch |
| `11.0-r12345` | a specific SVN revision (pin this for reproducible deployments) |

## What This Project Does

1. checks the ResourceSpace SVN repository once a day for the newest release
   branch and its latest revision
2. builds a new image when that revision has not been published yet
3. rebuilds once a week to pick up Ubuntu security updates
4. runs a smoke test (fresh install, admin login, dump, restore) and only then
   pushes to Docker Hub and GHCR

## Quick Start

```yaml
services:
  mariadb:
    image: mariadb:11.4
    environment:
      MARIADB_RANDOM_ROOT_PASSWORD: "1"
      MARIADB_DATABASE: resourcespace
      MARIADB_USER: resourcespace
      MARIADB_PASSWORD: change-me
    volumes:
      - db:/var/lib/mysql

  resourcespace:
    image: friedrichrehren/resourcespace:latest
    depends_on: [mariadb]
    ports:
      - "8080:80"
    environment:
      RS_BASEURL: http://localhost:8080
      RS_DB_PASSWORD: change-me
      RS_SCRAMBLE_KEY: "<openssl rand -hex 32>"
      RS_API_SCRAMBLE_KEY: "<openssl rand -hex 32>"
      RS_ADMIN_PASSWORD: "<your admin password>"
      RS_ADMIN_EMAIL: admin@example.com
      RS_WAIT_FOR_SYNC: "false"
    volumes:
      - data:/data

volumes:
  db:
  data:
```

A complete Portainer stack with Traefik labels and a two-way SharePoint sync
via `rclone bisync` is in [`stack/docker-compose.yml`](stack/docker-compose.yml).

## Environment Variables

| Variable | Default | Description |
| --- | --- | --- |
| `RS_BASEURL` | – (required) | public URL without trailing slash, e.g. `https://photo.example.com` |
| `RS_DB_HOST` | `mariadb` | database host |
| `RS_DB_PORT` | – | database port, if not 3306 |
| `RS_DB_NAME` | `resourcespace` | database name |
| `RS_DB_USER` | `resourcespace` | database user |
| `RS_DB_PASSWORD` | – (required) | database password |
| `RS_SCRAMBLE_KEY` | – (required) | secret, ≥ 32 characters. **Never change it** – password hashes depend on it |
| `RS_API_SCRAMBLE_KEY` | – (required) | secret for the API, ≥ 32 characters. Never change it |
| `RS_ADMIN_USERNAME` | `admin` | super admin created on first install |
| `RS_ADMIN_PASSWORD` | – (required on first install) | super admin password. **Must not be exactly 32 or 64 characters long** (see below) |
| `RS_ADMIN_EMAIL` | – (required on first install) | super admin e-mail, also used for system notifications |
| `RS_ADMIN_FULLNAME` | `Admin user` | display name of the super admin |
| `RS_ADMIN_FORCE_PASSWORD` | `false` | `true` sets the admin password from `RS_ADMIN_PASSWORD` at every start (lock-out recovery) |
| `RS_APPLICATION_NAME` | `ResourceSpace` | name shown in the UI |
| `RS_DEFAULT_LANGUAGE` | `de` | default UI language |
| `RS_EMAIL_FROM` | `noreply@<host>` | sender address |
| `RS_SMTP_HOST` | – | enables SMTP when set |
| `RS_SMTP_PORT` | `587` | SMTP port |
| `RS_SMTP_SECURE` | `tls` | `tls` or `ssl` |
| `RS_SMTP_USER` / `RS_SMTP_PASSWORD` | – | SMTP authentication |
| `RS_WAIT_FOR_SYNC` | `true` | wait for `/data/.rclone/ready` before starting (written by the sync container) |
| `RS_RESTORE_FROM_DUMP` | `true` | restore an empty database from `/data/db-dump/resourcespace.sql.gz` |
| `RS_DB_DUMP_SCHEDULE` | `0 */6 * * *` | cron schedule of the database dump |
| `RS_CRON_SCHEDULE` | `30 3 * * *` | cron schedule of ResourceSpace's `batch/cron.php` |
| `PHP_UPLOAD_MAX_FILESIZE` | `1G` | upload limit (also sets `post_max_size`) |
| `PHP_MEMORY_LIMIT` | `1G` | PHP memory limit |
| `PHP_MAX_EXECUTION_TIME` | `300` | PHP execution time in seconds |
| `TZ` | `Europe/Berlin` | PHP time zone |

Secrets can also be passed as files: `RS_DB_PASSWORD_FILE`,
`RS_SCRAMBLE_KEY_FILE`, `RS_API_SCRAMBLE_KEY_FILE`, `RS_ADMIN_PASSWORD_FILE`,
`RS_SMTP_PASSWORD_FILE`.

### Passwords with exactly 32 or 64 characters

ResourceSpace refuses every login whose password is exactly 32 or 64 characters
long, because such strings look like MD5/SHA-256 hashes (`rs_password_verify()`).
The image therefore rejects such an `RS_ADMIN_PASSWORD` with a clear error. The
same applies to passwords users set later in the UI.

## The Data Volume

```
/data
├── filestore/   originals, previews, slideshow images (served under /filestore)
│   └── plugins/ additional third-party plugins (PHP allowed here only)
├── db-dump/     resourcespace.sql.gz – latest database dump
├── config/      config.local.php – optional, included after the generated config
├── tmp/         temporary files
└── .rclone/     state of the optional sync container
```

Custom ResourceSpace settings go into `/data/config/config.local.php`:

```bash
docker exec -it <container> nano /data/config/config.local.php
```

```php
<?php
$plugins[] = 'tms_link';
$watermark = 'gfx/watermark.png';
```

## Additional Plugins

All plugins that ship with ResourceSpace can be activated and configured in the
UI as usual. Third-party or custom plugins are placed in the data volume –
ResourceSpace loads plugins from `filestore/plugins/` in addition to its own
`plugins/` folder:

```bash
docker cp my_plugin <container>:/data/filestore/plugins/
docker exec <container> chown -R www-data:www-data /data/filestore/plugins/my_plugin
```

Then activate it in the plugin management of the admin area. PHP execution is allowed in
`filestore/plugins/` only; everything else in the filestore stays blocked.

Anyone who can write to `filestore/plugins/` can run code in the container.
The example stack therefore excludes this folder from the SharePoint sync.

## Restore

Database and media can be restored from the data volume alone: start the
container with the restored `/data` and an **empty** database. The entrypoint
imports `db-dump/resourcespace.sql.gz` before ResourceSpace starts. Changes made
after the last dump (at most 6 hours by default) are lost; the media files
are not.

`RS_SCRAMBLE_KEY` must be the same as before, otherwise no password matches.

## Differences to the Official Image

The official [`resourcespace/docker`](https://github.com/resourcespace/docker)
repository only provides a Dockerfile; its GHCR package is not public. This
image keeps the same Ubuntu base and runtime packages, but

- does not ship build tools, Subversion, Postfix or OpenCV (facial recognition
  is deprecated upstream) – configure SMTP instead of local mail
- keeps the application code read-only; additional plugins go into
  `/data/filestore/plugins/` (see below)
- replaces the web installer with environment variables

## Repository Setup

Secrets for the workflows (same as `yt-dlp-docker`):

| Secret | Purpose |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub user |
| `DOCKERHUB_TOKEN` | Docker Hub access token (read/write) |

Optional repository variable `RS_RELEASE` pins the release branch (e.g. `11.0`);
default is the newest branch.

After the first run, set the GHCR package visibility to **public**
(Package settings → Change visibility), otherwise pulls without login fail.
