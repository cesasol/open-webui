#!/bin/bash

IMAGE_NAME="open-webui"
VERSION="0.5.16"
IMAGE_TAG="$IMAGE_NAME:$VERSION"

# declare -a DEVICES=("cpu" "rocm" "cuda", "xpu")
declare -a DEVICES=("cpu")

HASH="$(git rev-parse --short HEAD)"

for RUNTIME_DEVICE in "${DEVICES[@]}"; do
    nerdctl builder build \
        -t "$IMAGE_TAG-$RUNTIME_DEVICE" \
        --build-arg BUILD_HASH="$(git rev-parse --short HEAD)" \
        --build-arg RUNTIME_DEVICE="$RUNTIME_DEVICE" .
    # podman build \
    #     --format docker \
    #     -t "$IMAGE_TAG-$RUNTIME_DEVICE" \
    #     --build-arg BUILD_HASH="$HASH" \
    #     --layers \
    #     --build-arg RUNTIME_DEVICE="$RUNTIME_DEVICE" .

done


# any sentence transformer model; models to use can be found at https://huggingface.co/models?library=sentence-transformers
# Leaderboard: https://huggingface.co/spaces/mteb/leaderboard
# for better performance and multilangauge support use "intfloat/multilingual-e5-large" (~2.5GB) or "intfloat/multilingual-e5-base" (~1.5GB)
# IMPORTANT: If you change the embedding model (sentence-transformers/all-MiniLM-L6-v2) and vice versa, you aren't able to use RAG Chat with your previous documents loaded in the WebUI! You need to re-embed them.
# ARG USE_EMBEDDING_MODEL="nomic-ai/nomic-embed-text-v2-moe"
# ARG USE_RERANKING_MODEL="Cohere/rerank-v3.5"
# Tiktoken encoding name; models to use can be found at https://huggingface.co/models?library=tiktoken
# ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"