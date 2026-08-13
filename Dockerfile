# syntax=docker/dockerfile:1.26

# The Godot export is NOT built here. Producing it needs the engine plus a
# 1.2GB template download, which has no business in an image build — CI runs
# the export once and this copies the result in. `build/web` must therefore
# already exist in the build context; see .github/workflows/ci.yaml, or run
#
#     mkdir -p build/web && godot --headless --export-release "Web" build/web/index.html
#
# before building this by hand.

FROM eclipse-temurin:25-jdk AS build

WORKDIR /app
COPY server/ .

RUN ./gradlew clean installDist \
    && mkdir -p /app/appjar \
    && mv /app/build/install/egg/lib/egg-*.jar /app/appjar/

FROM eclipse-temurin:25-jre AS deploy

# Split deliberately: third-party dependencies are a stable layer that stays
# cached between builds, while the app's own jar is a small one that changes on
# every commit. A fat jar would be a single layer invalidated by both.
COPY --from=build /app/build/install/egg/bin /opt/app/bin
COPY --from=build /app/build/install/egg/lib /opt/app/lib

COPY --from=build /app/appjar/ /opt/app/lib/

# The exported game, and the generated art the pages are built from. These
# paths are what application.conf already defaults to, so the image needs no
# environment of its own — EGG_STORE, EGG_WEB and EGG_ASSETS exist to point a
# local run somewhere else, not to configure this.
COPY build/web/ /opt/app/web/
COPY assets/generated/ /opt/app/assets/

# No OpenTelemetry agent, unlike the other services in this cluster — their
# Dockerfiles ADD one and set JAVA_OPTS, so its absence here is a decision, not
# an omission. A new otel setup is being built out in flux-home and reaches
# hetzner after that; wiring this one up beforehand would mean guessing at the
# arrangement. The start script honours JAVA_OPTS, so adding the agent later is
# a Dockerfile line and an env var, nothing more.

EXPOSE 8080

# /data holds scores.jsonl and is a volume in the cluster. Declared so a plain
# `docker run` keeps scores across restarts instead of silently losing them in
# the container layer.
VOLUME ["/data"]

CMD ["/opt/app/bin/egg"]
