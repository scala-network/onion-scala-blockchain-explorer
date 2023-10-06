# Use ubuntu:20.04 as base for builder stage image
FROM ubuntu:20.04 as builder

# Set Scala branch/tag to be used for scalad compilation

ARG SCALA_BRANCH=release-v0.18

# Added DEBIAN_FRONTEND=noninteractive to workaround tzdata prompt on installation
ENV DEBIAN_FRONTEND="noninteractive"

# Install dependencies for scalad and xlablocks compilation
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    cmake \
    miniupnpc \
    graphviz \
    doxygen \
    pkg-config \
    ca-certificates \
    zip \
    libboost-all-dev \
    libunbound-dev \
    libunwind8-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libgtest-dev \
    libreadline-dev \
    libzmq3-dev \
    libsodium-dev \
    libhidapi-dev \
    libhidapi-libusb0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set compilation environment variables
ENV CFLAGS='-fPIC'
ENV CXXFLAGS='-fPIC'
ENV USE_SINGLE_BUILDDIR 1
ENV BOOST_DEBUG         1

WORKDIR /root

# Clone and compile scalad with all available threads
ARG NPROC
RUN git clone --recursive --branch ${SCALA_BRANCH} https://github.com/scala-project/scala.git \
    && cd scala \
    && test -z "$NPROC" && nproc > /nproc || echo -n "$NPROC" > /nproc && make -j"$(cat /nproc)"


# Copy and cmake/make xlablocks with all available threads
COPY . /root/onion-scala-blockchain-explorer/
WORKDIR /root/onion-scala-blockchain-explorer/build
RUN cmake .. && make -j"$(cat /nproc)"

# Use ldd and awk to bundle up dynamic libraries for the final image
RUN zip /lib.zip $(ldd xlablocks | grep -E '/[^\ ]*' -o)

# Use ubuntu:20.04 as base for final image
FROM ubuntu:20.04

# Added DEBIAN_FRONTEND=noninteractive to workaround tzdata prompt on installation
ENV DEBIAN_FRONTEND="noninteractive"

# Install unzip to handle bundled libs from builder stage
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /lib.zip .
RUN unzip -o lib.zip && rm -rf lib.zip

# Add user and setup directories for scalad and xlablocks
RUN useradd -ms /bin/bash scala \
    && mkdir -p /home/scala/.bitscala \
    && chown -R scala:scala /home/scala/.bitscala
USER scala

# Switch to home directory and install newly built xlablocks binary
WORKDIR /home/scala
COPY --chown=scala:scala --from=builder /root/onion-scala-blockchain-explorer/build/xlablocks .
COPY --chown=scala:scala --from=builder /root/onion-scala-blockchain-explorer/build/templates ./templates/

# Expose volume used for lmdb access by xlablocks
VOLUME /home/scala/.bitscala

# Expose default explorer http port
EXPOSE 8081

ENTRYPOINT ["/bin/sh", "-c"]

# Set sane defaults that are overridden if the user passes any commands
CMD ["./xlablocks --enable-json-api --enable-autorefresh-option  --enable-pusher"]
