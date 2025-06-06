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

# Install viu
RUN cargo install viu

# -------- Stage 2: Final image --------
FROM debian:bullseye-slim

# Install required runtime packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq && \
    rm -rf /var/lib/apt/lists/*

# Copy viu from builder
COPY --from=builder /root/.cargo/bin/viu /usr/local/bin/viu

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
