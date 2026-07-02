# Image for the scheduled database-backup Cloud Run Job: pg_dump + gcloud storage.
# Based on the Cloud SDK image (has `gcloud`), plus the PostgreSQL client. We
# install postgresql-client-18 from PGDG so pg_dump matches/exceeds the Neon
# server version (Neon runs Postgres 18; a newer pg_dump can dump an older
# server, but not vice versa).
FROM google/cloud-sdk:slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release \
 && install -d /usr/share/postgresql-common/pgdg \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
 && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client-18 \
 && rm -rf /var/lib/apt/lists/*

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
