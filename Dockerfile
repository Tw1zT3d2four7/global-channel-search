FROM debian:bullseye-slim

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq && \
    rm -rf /var/lib/apt/lists/*
    
ENV TERM=xterm

WORKDIR /app

# Copy the entire repo content (including lib/)
COPY . .

# Make the script executable
RUN chmod +x globalstationsearch.sh

CMD ["./globalstationsearch.sh"]
