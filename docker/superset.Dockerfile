FROM apache/superset:latest
USER root
RUN /app/docker/pip-install.sh clickhouse-connect
USER superset