# syntax=docker/dockerfile:1
# Initialize device type args
# use build args in the docker build command with --build-arg="BUILDARG=true"
ARG USE_OLLAMA=false
# Tested with cu117 for CUDA 11 and cu121 for CUDA 12 (default)
ARG USE_CUDA_VER=cu121
ARG USE_ROCM_VER=6.2.4
# any sentence transformer model; models to use can be found at https://huggingface.co/models?library=sentence-transformers
# Leaderboard: https://huggingface.co/spaces/mteb/leaderboard
# for better performance and multilangauge support use "intfloat/multilingual-e5-large" (~2.5GB) or "intfloat/multilingual-e5-base" (~1.5GB)
# IMPORTANT: If you change the embedding model (sentence-transformers/all-MiniLM-L6-v2) and vice versa, you aren't able to use RAG Chat with your previous documents loaded in the WebUI! You need to re-embed them.
# ARG USE_EMBEDDING_MODEL=nomic-ai/nomic-embed-text-v2-moe
ARG USE_EMBEDDING_MODEL=jinaai/jina-embeddings-v2-base-es
ARG USE_RERANKING_MODEL=CohereRerank/bge-reranker-large
# vgarg/fw_identification_model_e5_large_v8_03_07_2024
# Tiktoken encoding name; models to use can be found at https://huggingface.co/models?library=tiktoken
ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"

ARG BUILD_HASH=dev-build
# Override at your own risk - non-root configurations are untested
ARG UID=0
ARG GID=0

# Can be cuda, rocm or cpu
ARG RUNTIME_DEVICE=cpu

######## WebUI frontend ########
FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS base-front
ARG BUILD_HASH

# PNPM
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable
WORKDIR /app

COPY package.json pnpm-lock.yaml *.ts *.js ./
COPY ./src ./src
COPY ./static ./static
COPY ./scripts ./scripts

# Build layer
FROM base-front AS front-build
ENV APP_BUILD_HASH=${BUILD_HASH}
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
RUN pnpm run build

######## WebUI backend ########
FROM python:3.11-slim-bookworm AS base

# Use args
ARG UID
ARG GID

WORKDIR /app/backend

ENV HOME=/root

# Create user and group if not root
RUN if [ $UID -ne 0 ]; then \
    if [ $GID -ne 0 ]; then \
    addgroup --gid $GID app; \
    fi; \
    adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma
RUN echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id

# Make sure the user has access to the app and root directory
RUN chown -R $UID:$GID /app $HOME


# Cache apt
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install pandoc, netcat and gcc. Then RAG OCR. And cleanup
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install -y --no-install-recommends git build-essential pandoc gcc netcat-openbsd curl jq &&\
    apt install -y --no-install-recommends gcc python3-dev &&\
    apt install -y --no-install-recommends ffmpeg libsm6 libxext6

# copy embedding weight from build
# RUN mkdir -p /root/.cache/chroma/onnx_models/all-MiniLM-L6-v2
# COPY --from=build /app/onnx /root/.cache/chroma/onnx_models/all-MiniLM-L6-v2/onnx

# Install torchvision based on the target device
FROM base AS base-nvidia
ARG USE_CUDA_VER
ONBUILD RUN --mount=type=cache,target=/root/.cache pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/$USE_CUDA_VER 
ENV USE_CUDA_DOCKER=true

FROM base AS base-rocm
ARG USE_ROCM_VER
ONBUILD RUN --mount=type=cache,target=/root/.cache pip3 install torch torchvision torchaudio pytorch-triton-rocm --index-url https://download.pytorch.org/whl/rocm$USE_ROCM_VER 
ENV USE_ROCM_DOCKER=true

FROM base AS base-cpu
ONBUILD RUN --mount=type=cache,target=/root/.cache pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu 
ENV USE_CPU_DOCKER=true

######## Final Image ########
FROM base-${RUNTIME_DEVICE} as build
ARG BUILD_HASH
ARG RUNTIME_DEVICE
ARG UID
ARG GID
ARG RUNTIME_DEVICE
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_ROCM_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL

USER $UID:$GID

LABEL RUNTIME_DEVICE=${RUNTIME_DEVICE}
## Basis ##
ENV ENV=prod \
    PORT=8080 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    RUNTIME_DEVICE_DOCKER=${RUNTIME_DEVICE} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_ROCM_DOCKER_VER=${USE_ROCM_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL} \
    WEBUI_BUILD_VERSION=${BUILD_HASH}

ENV DOCKER=true

## Basis URL Config ##
ENV OLLAMA_BASE_URL="/ollama" \
    OPENAI_API_BASE_URL=""

## API Key and Security Config ##
ENV OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="" \
    SCARF_NO_ANALYTICS=true \
    DO_NOT_TRACK=true \
    ANONYMIZED_TELEMETRY=false

#### Other models #########################################################
## whisper TTS model settings ##
ENV WHISPER_MODEL="distil-small.en" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models"

## RAG Embedding model settings ##
ENV RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL_DOCKER" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL_DOCKER" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models"

## Tiktoken model settings ##
ENV TIKTOKEN_ENCODING_NAME="cl100k_base" \
    TIKTOKEN_CACHE_DIR="/app/backend/data/cache/tiktoken"

## Hugging Face download cache ##
ENV HF_HOME="/app/backend/data/cache/embedding/models"

## Torch Extensions ##
ENV TORCH_EXTENSIONS_DIR="/.cache/torch_extensions"

#### Other models ##########################################################

# install python dependencies
COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt
RUN --mount=type=cache,target=/root/.cache pip3 install uv
RUN --mount=type=cache,target=/root/.cache uv pip install --system -r requirements.txt 

# Download models
RUN <<EOT
#!/usr/bin/env python
import os
from sentence_transformers import SentenceTransformer
from faster_whisper import WhisperModel
import tiktoken
SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')
WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])
tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])
EOT

# copy backend files
COPY --chown=$UID:$GID ./backend .

# copy built frontend files
COPY --chown=$UID:$GID --from=front-build /app/build /app/build
COPY --chown=$UID:$GID --from=front-build /app/package.json /app/package.json
COPY --chown=$UID:$GID  ./CHANGELOG.md /app/CHANGELOG.md

# Setup volumes
RUN mkdir -p /usr/share/ollama/.ollama/models /root/.ollama/models
VOLUME [ "/app/backend/data", "/usr/share/ollama/.ollama/models", "/root/.ollama/models" ]

# Integrated ollama?
FROM build
ARG USE_OLLAMA

# RUN if ["${USE_OLLAMA}" == 'true']; then; curl -fsSL https://ollama.com/install.sh | sh; fi
EXPOSE 8080
HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1
CMD [ "bash", "start.sh"]
