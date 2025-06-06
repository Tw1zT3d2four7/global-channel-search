FROM debian:bullseye-slim

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq && \
    rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy script into the container
COPY globalstationsearch.sh .

# Make the script executable
RUN chmod +x globalstationsearch.sh

# Set the default command to execute the script
CMD ["./globalstationsearch.sh"]
