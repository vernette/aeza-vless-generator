FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y --no-install-recommends \
    curl \
    openssl \
    jq \
    qrencode \
    ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY aeza-vless-generator.sh .

RUN chmod +x aeza-vless-generator.sh

ENTRYPOINT ["bash", "./aeza-vless-generator.sh"]
