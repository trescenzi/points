FROM ghcr.io/gleam-lang/gleam:v1.11.1-elixir-alpine

COPY . /build/

ENV ERLANG_COOKIE="OmNomNomNom"
#ENV ERL_AFLAGS = '-proto_dist inet6_tcp -name ${FLY_APP_NAME}-${FLY_IMAGE_REF##*-}@${FLY_PRIVATE_IP} -setcookie foo'
ENV ERLANG_BASENAME="erlang_node"
ENV DNS_CLUSTER_QUERY="erlang_node"

RUN apk add gcc build-base git \
  && cd build \
  && gleam deps update \
  && rm -r build/packages/lamb/test \
  && gleam export erlang-shipment \
  && mv build/erlang-shipment /app \
  && mv priv/ /app \
  && mv set_erlang_flags.sh /app \
  && rm -r /build \
  && apk del gcc build-base \
  && addgroup -S points \
  && adduser -S points -G points \
  && chown -R points /app

USER points
WORKDIR /app
CMD ["sh", "/app/set_erlang_flags.sh"]
