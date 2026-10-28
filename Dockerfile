# syntax=docker/dockerfile:1.7
#
# Portfolio image: CRA static build served by unprivileged nginx.
#
# Build (ARM64 / Graviton):
#   docker buildx build --platform linux/arm64 -t portfolio:local --load .
#
# The builder stage runs on the build host's native platform ($BUILDPLATFORM):
# the CRA output is plain HTML/JS/CSS and does not depend on the CPU, so there
# is no reason to run npm under QEMU emulation. Only the runtime stage is arm64.
#
# Base images are pinned by multi-arch index digest for reproducible builds.
# Bump the tag and digest together (`docker buildx imagetools inspect <tag>`).
ARG NODE_IMAGE=node:24-alpine@sha256:06d7adf3e0ef61a13f1d28682726366f97a15aa1888c934d3ecec86c33918b53
ARG NGINX_IMAGE=nginxinc/nginx-unprivileged:alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e

# ---------------------------------------------------------------- builder ----
FROM --platform=$BUILDPLATFORM ${NODE_IMAGE} AS builder
WORKDIR /app

# CI=true             : treat warnings as errors, no interactive prompts.
# GENERATE_SOURCEMAP  : don't ship source maps (size + source disclosure).
# INLINE_RUNTIME_CHUNK: keep the webpack runtime out of index.html so the CSP
#                       can use script-src 'self' without 'unsafe-inline'.
# NODE_ENV is deliberately NOT set to production here: `npm ci` would then skip
# devDependencies and the `patch-package` postinstall hook would fail.
ENV CI=true \
    GENERATE_SOURCEMAP=false \
    INLINE_RUNTIME_CHUNK=false \
    NPM_CONFIG_UPDATE_NOTIFIER=false

# patches/ must exist before `npm ci`, because postinstall runs patch-package.
COPY package.json package-lock.json ./
COPY patches/ ./patches/
RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund

COPY tsconfig.json ./
COPY public/ ./public/
COPY src/ ./src/
RUN npm run build

# ---------------------------------------------------------------- runtime ----
FROM ${NGINX_IMAGE} AS runtime

LABEL org.opencontainers.image.title="portfolio" \
      org.opencontainers.image.description="React portfolio served by nginx-unprivileged" \
      org.opencontainers.image.source="https://github.com/datng17/ecs-portfolio" \
      org.opencontainers.image.licenses="MIT"

# Keep container stdout to the JSON access log only.
ENV NGINX_ENTRYPOINT_QUIET_LOGS=1

# Patch between upstream rebuilds (see evidence/03-trivy.txt):
# - curl/libcurl are not used at runtime (the HEALTHCHECK uses busybox wget)
#   and carried most of the CVEs, so remove them.
# - apk upgrade pulls Alpine security fixes (brotli-libs, musl, zlib, ...).
#   Trade-off: less byte-for-byte reproducible than a pure digest pin, but the
#   pinned upstream digest was already the latest and still had fixable HIGHs.
USER 0
RUN apk del --no-cache curl \
 && apk upgrade --no-cache \
 && rm -rf /var/cache/apk/*

# Config and content are owned by root and read-only for the nginx user (101).
COPY docker/nginx/nginx.conf            /etc/nginx/nginx.conf
COPY docker/nginx/default.conf          /etc/nginx/conf.d/default.conf
COPY docker/nginx/security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY docker/nginx/real-ip.conf          /etc/nginx/snippets/real-ip.conf
COPY --from=builder /app/build          /usr/share/nginx/portfolio

USER 101
EXPOSE 8080

# The only writable paths under a read-only root filesystem (pid file, temp and cache files).
# On Fargate the task definition mounts ephemeral volumes here. A Fargate bind mount is
# root-owned 0755 unless the image declares the same path as VOLUME, in which case ECS copies
# the image's contents and ownership (/tmp 1777, /var/cache/nginx owned by 101). Locally,
# docker-compose mounts tmpfs over the same paths.
VOLUME ["/tmp", "/var/cache/nginx"]

# busybox wget ships in the base image; no extra packages needed.
# Exec form: no shell needed, and busybox wget exits 1 on any failure.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
