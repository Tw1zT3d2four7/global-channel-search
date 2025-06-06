FROM debian:bullseye-slim

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        curl \
        jq && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY globalstationsearch.sh .

RUN chmod +x globalstationsearch.sh

CMD ["./globalstationsearch.sh"]
