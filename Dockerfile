FROM ghcr.io/gleam-lang/gleam:v1.11.1-elixir-alpine

COPY . /build/

RUN apk add gcc build-base git \
  && cd /build \
  && gleam deps update \
  && rm -r build/packages/lamb/test \
  && gleam export erlang-shipment \
  && mv build/erlang-shipment /app \
  && rm -r /build \
  && apk del gcc build-base \
  && addgroup -S points \
  && adduser -S points -G points \
  && chown -R points /app

USER points
WORKDIR /app
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]
