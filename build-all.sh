#!/bin/bash

IMAGE_NAME="open-webui"
VERSION="0.5.12"
IMAGE_TAG="$IMAGE_NAME:$VERSION"

docker build -t "$IMAGE_TAG-rocm"   --build-arg RUNTIME_DEVICE=rocm .
docker build -t "$IMAGE_TAG-cpu"    --build-arg RUNTIME_DEVICE=cpu .
docker build -t "$IMAGE_TAG-nvidia" --build-arg RUNTIME_DEVICE=nvidia .

# Build ollama variants
# docker build -t "$IMAGE_TAG-rocm-ollama"   --build-arg USE_OLLAMA=true --build-arg RUNTIME_DEVICE=rocm .
# docker build -t "$IMAGE_TAG-cpu-ollama"    --build-arg USE_OLLAMA=true --build-arg RUNTIME_DEVICE=cpu .
# docker build -t "$IMAGE_TAG-nvidia-ollama" --build-arg USE_OLLAMA=true --build-arg RUNTIME_DEVICE=nvidia .

# Tag CPU as latest
docker build -t "$IMAGE_NAME:latest"    --build-arg RUNTIME_DEVICE=cpu .

# Push images
docker push "$IMAGE_NAME"