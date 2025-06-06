#!/bin/bash

# Start container only if it's not already running
docker ps -q -f name=global-channel-search | grep -q . || docker compose up -d

# Attach to the container for interactive use
docker attach global-channel-search

# After detach (or exit), stop the container
docker stop global-channel-search

