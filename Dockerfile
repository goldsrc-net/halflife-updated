# Emscripten Build Environment
FROM emscripten/emsdk:4.0.22

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies and newer CMake via pip
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    ca-certificates \
    build-essential \
    && pip3 install cmake \
    && apt-get remove -y cmake \
    && apt-get -y autoremove \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

CMD ["/bin/bash"]
