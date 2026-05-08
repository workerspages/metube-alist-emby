# ============================================
# Stage 1: Build MeTube UI
# ============================================
FROM --platform=$BUILDPLATFORM node:lts-alpine AS metube-builder

WORKDIR /build
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/alexta69/metube.git .

WORKDIR /build/ui
RUN corepack enable && corepack prepare pnpm --activate
RUN CI=true pnpm install && pnpm run build

# ============================================
# Stage 2: Final image
# ============================================
FROM python:3.13-slim

ARG TARGETARCH

# ------------------------------------------
# Install system dependencies
# ------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor \
    ca-certificates \
    ffmpeg \
    unzip \
    aria2 \
    coreutils \
    gosu \
    curl \
    wget \
    tini \
    build-essential \
    gpg \
    jq \
    fuse3 \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------
# Install Caddy
# ------------------------------------------
RUN curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
      | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
      | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt-get update \
    && apt-get install -y caddy \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------
# Install Emby Server
# ------------------------------------------
RUN EMBY_VERSION=$(curl -s https://api.github.com/repos/MediaBrowser/Emby.Releases/releases/latest \
      | jq -r '.tag_name') \
    && echo "Installing Emby ${EMBY_VERSION} for ${TARGETARCH}" \
    && curl -L -o /tmp/emby.deb \
      "https://github.com/MediaBrowser/Emby.Releases/releases/download/${EMBY_VERSION}/emby-server-deb_${EMBY_VERSION}_${TARGETARCH}.deb" \
    && dpkg --unpack /tmp/emby.deb \
    && rm -f /var/lib/dpkg/info/emby-server.postinst \
    && dpkg --configure emby-server \
    && apt-get install -f -y --no-install-recommends \
    && rm -f /tmp/emby.deb

# ------------------------------------------
# Install Alist
# ------------------------------------------
RUN curl -L -o /tmp/alist.tar.gz \
      "https://github.com/AlistGo/alist/releases/latest/download/alist-linux-${TARGETARCH}.tar.gz" \
    && tar -xzf /tmp/alist.tar.gz -C /usr/local/bin/ \
    && chmod +x /usr/local/bin/alist \
    && rm -f /tmp/alist.tar.gz

# ------------------------------------------
# Install rclone (mount Alist WebDAV for Emby)
# ------------------------------------------
RUN curl -L -o /tmp/rclone.zip \
      "https://downloads.rclone.org/rclone-current-linux-${TARGETARCH}.zip" \
    && cd /tmp && unzip -q rclone.zip \
    && cp /tmp/rclone-*/rclone /usr/local/bin/ \
    && chmod +x /usr/local/bin/rclone \
    && rm -rf /tmp/rclone*

# ------------------------------------------
# Install MeTube
# ------------------------------------------
WORKDIR /app/metube
COPY --from=metube-builder /build/pyproject.toml /build/uv.lock ./

RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh \
    && UV_PROJECT_ENVIRONMENT=/usr/local uv sync --frozen --no-dev --compile-bytecode \
    && uv cache clean \
    && rm -f /usr/local/bin/uv /usr/local/bin/uvx /usr/local/bin/uvw

# Install Deno (used by MeTube) - download binary directly to avoid QEMU crash
RUN case "$TARGETARCH" in \
      amd64) DENO_ARCH="x86_64" ;; \
      arm64) DENO_ARCH="aarch64" ;; \
    esac \
    && curl -fsSL -o /tmp/deno.zip \
      "https://github.com/denoland/deno/releases/latest/download/deno-${DENO_ARCH}-unknown-linux-gnu.zip" \
    && unzip -o -q /tmp/deno.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/deno \
    && rm -f /tmp/deno.zip

COPY --from=metube-builder /build/app ./app
COPY --from=metube-builder /build/ui/dist/metube ./ui/dist/metube

# Clean up build dependencies
RUN apt-get purge -y --auto-remove build-essential \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------
# Copy configuration files
# ------------------------------------------
COPY Caddyfile /etc/caddy/Caddyfile
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
COPY rclone-mount.sh /rclone-mount.sh
COPY portal /srv/portal

RUN chmod +x /entrypoint.sh /rclone-mount.sh

# Create data directories
RUN mkdir -p /downloads /config/alist /config/emby /media/alist /.cache \
    && chmod 777 /.cache

# ------------------------------------------
# Default environment variables
# Users can override these with docker run -e
# ------------------------------------------

ENV TZ=Asia/Shanghai

# MeTube defaults
ENV DOWNLOAD_DIR=/downloads
ENV STATE_DIR=/downloads/.metube
ENV TEMP_DIR=/downloads
ENV YTDL_OPTIONS="{}"
ENV OUTPUT_TEMPLATE="%(title).100B.%(ext)s"
ENV OUTPUT_TEMPLATE_CHAPTER="%(title)s - %(section_number)s %(section_title)s.%(ext)s"
ENV DARK_MODE=true
ENV MAX_CONCURRENT_DOWNLOADS=5
ENV CREATE_CUSTOM_DIRS=true
ENV ALLOW_YTDL_OPTIONS_OVERRIDES=false
ENV CLEAR_COMPLETED_AFTER=120

# Emby defaults
ENV EMBY_PROGRAMDATA=/config/emby

# Alist defaults
ENV ALIST_DATA=/config/alist

# Container port
ENV PORT=8080

EXPOSE 8080

VOLUME ["/downloads", "/config"]

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
