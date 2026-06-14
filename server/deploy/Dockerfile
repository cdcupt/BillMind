# Multi-stage build. Context is the repo root so the path dependency
# `../shared/BillMindCore` (a sibling of server/) resolves inside the image.
FROM swift:6.0-jammy AS build
WORKDIR /build
# Resolve dependencies first (better layer caching), then build.
COPY shared ./shared
COPY server/Package.swift ./server/Package.swift
WORKDIR /build/server
RUN swift package resolve
COPY server/Sources ./Sources
RUN swift build -c release --product App

# --- runtime image ---
FROM swift:6.0-jammy-slim
WORKDIR /app
COPY --from=build /build/server/.build/release/App ./App
# Resources (migrations etc.) would be copied here as they're added.
EXPOSE 8080
ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
