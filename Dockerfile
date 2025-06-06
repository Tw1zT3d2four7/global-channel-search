FROM debian:bullseye-slim

# Install required packages plus dependencies for Rust build and viu
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq \
        build-essential \
        ca-certificates \
        git \
        libssl-dev \
        pkg-config && \
    rm -rf /var/lib/apt/lists/*

# Install Rust (non-interactive)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# Add cargo to PATH
ENV PATH="/root/.cargo/bin:${PATH}"

# Install viu using cargo
RUN cargo install viu

ENV TERM=xterm

WORKDIR /app

# Copy the entire repo content (including lib/)
COPY . .

# Make the script executable
RUN chmod +x globalstationsearch.sh

CMD ["./globalstationsearch.sh"]
