FROM docker.viriciti.com/device/armhf-alpine-node

# Create app directory
RUN mkdir -p /app
WORKDIR /app

# Install app dependencies
COPY node_modules /app/node_modules

COPY build/actions /app/actions
COPY build/helpers /app/helpers
COPY build/lib /app/lib
COPY build/manager /app/manager
COPY build/main.js /app/main.js
COPY config /app/config
COPY package.json /app/package.json

ARG DOCKER_REGISTRY_TOKEN=xxx

ENV DOCKER_REGISTRY_TOKEN=${DOCKER_REGISTRY_TOKEN}

CMD ["node", "/app/main.js"]
