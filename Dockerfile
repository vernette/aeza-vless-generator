FROM alpine:3.21

RUN apk add --no-cache \
  curl \
  jq \
  libqrencode-tools \
  openssl \
  bash

WORKDIR /app

COPY aeza-vless-generator.sh .

RUN chmod +x aeza-vless-generator.sh
