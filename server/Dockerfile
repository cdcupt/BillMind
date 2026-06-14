# BillMind 2.0 server — multi-stage Swift build.
#
# IMPORTANT: build with the *repo root* as context (not server/), because the
# package depends on ../shared/BillMindCore via a local path:
#     docker build -f server/Dockerfile -t billmind-server .
# docker-compose.yml already sets `context: .` for this reason.

# ── Build ────────────────────────────────────────────────────────────────────
FROM swift:6.0-jammy AS build

# OS deps for building (libpq headers etc. come via SwiftPM packages).
RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies against just the manifests first, so the (slow) fetch
# layer is cached until a Package.swift / Package.resolved actually changes.
COPY ./server/Package.swift ./server/Package.resolved ./server/
COPY ./shared/BillMindCore/Package.swift ./shared/BillMindCore/
# Honors the committed Package.resolved pins (copied above).
RUN cd server && swift package resolve

# Copy the full sources for both packages and build the release binary.
COPY ./shared ./shared
COPY ./server ./server
WORKDIR /build/server
RUN swift build -c release --product App --static-swift-stdlib

# Stage the binary (required) into a clean tree.
RUN mkdir -p /staging \
  && cp "$(swift build -c release --show-bin-path)/App" /staging/

# Stage any SwiftPM resource bundles (optional — this app ships none today, so
# the find is allowed to match nothing without failing the build).
RUN BIN="$(swift build -c release --show-bin-path)" \
  && find -L "$BIN/" -regex '.*\.resources$' -exec cp -Ra {} /staging/ \; -o -true

# ── Run ──────────────────────────────────────────────────────────────────────
FROM ubuntu:jammy

RUN apt-get update -qq \
  && apt-get install -y --no-install-recommends ca-certificates tzdata curl libcurl4 \
  && rm -rf /var/lib/apt/lists/* \
  && useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app

USER vapor:vapor
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
