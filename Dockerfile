# Use a lightweight official Python image
FROM python:3.10-slim

# Set the working directory
WORKDIR /app

# Install required system packages (for building some Python wheels)
RUN apt-get update && apt-get install -y \
    gcc \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy all project files into the container
COPY . .

# Install Python dependencies
#RUN pip install --no-cache-dir -r requirements.txt

# Run the script
CMD ["python", "main.py"]

