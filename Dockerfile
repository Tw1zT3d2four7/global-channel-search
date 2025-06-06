# -------- Stage 1: Build viu from source --------
FROM rust:1.79-slim as builder

# Install required dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Set cargo bin path
ENV CARGO_BIN_DIR=/usr/local/cargo/bin
ENV PATH="${CARGO_BIN_DIR}:${PATH}"

# Install viu
RUN cargo install viu --version 1.4.0

# Debug: check where viu was installed
RUN find / -type f -name viu

# -------- Stage 2: Final image --------
FROM debian:bullseye-slim

# Install required runtime packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq && \
    rm -rf /var/lib/apt/lists/*

# Copy viu from builder (based on actual cargo path)
COPY --from=builder /usr/local/cargo/bin/viu /usr/local/bin/viu

# Set terminal type
ENV TERM=xterm

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Make script executable
RUN chmod +x globalstationsearch.sh

# Set default command
CMD ["./globalstationsearch.sh"]
