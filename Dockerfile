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
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""

# Tiktoken encoding name; models to use can be found at https://huggingface.co/models?library=tiktoken
ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"


# Can be cuda, rocm or cpu
ARG RUNTIME_DEVICE=cpu

######## WebUI frontend ########
FROM --platform=$BUILDPLATFORM node:22-alpine AS base-front
ARG BUILD_HASH
WORKDIR /app

# PNPM
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"

COPY package.json pnpm-lock.yaml *.ts *.js /app/
COPY src /app/src
COPY static /app/static
COPY scripts /app/scripts

RUN corepack enable

# Build layer
FROM base-front AS front-build
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile
RUN pnpm run build

######## WebUI backend base ########
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS base

ENV UV_CACHE_DIR=/var/cache/uv
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy

# Cache apt
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

# Install pandoc, netcat and gcc. Then RAG OCR. And cleanup
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt update && \
    apt install -y --no-install-recommends git build-essential pandoc gcc netcat-openbsd curl jq gcc python3-dev ffmpeg libsm6 libxext6

######## WebUI backend ########
FROM base AS backend
WORKDIR /app

# Setup volumes
RUN mkdir -p /app/backend/data /var/lib/ollama /var/cache/uv
VOLUME [ "WEBUI_DATA:/app/backend/data", "OLLAMA_MODELS:/var/lib/ollama" ]

# Copy backend files
COPY *.toml uv.lock *.json LICENSE README.md CHANGELOG.md *.py /app/
COPY backend /app/backend

# copy built frontend files
COPY --from=front-build /app/build /app/build

######## WebUI dependencies ########
FROM backend AS base-nvidia
ARG USE_CUDA_VER
ONBUILD RUN --mount=type=cache,id=UV_CACHE,target=$UV_CACHE_DIR uv sync --frozen --extra $USE_CUDA_VER
ENV USE_CUDA_DOCKER=true

FROM backend AS base-rocm
ARG USE_ROCM_VER
ONBUILD RUN --mount=type=cache,id=UV_CACHE,target=$UV_CACHE_DIR uv sync --extra rocm --frozen
ENV USE_ROCM_DOCKER=true

FROM backend AS base-cpu
ONBUILD RUN --mount=type=cache,id=UV_CACHE,target=$UV_CACHE_DIR uv sync --extra cpu --frozen
ENV USE_CPU_DOCKER=true

######## Final Image ########
FROM base-${RUNTIME_DEVICE} as build
ARG RUNTIME_DEVICE
ARG RUNTIME_DEVICE
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_ROCM_VER
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL

LABEL RUNTIME_DEVICE=${RUNTIME_DEVICE}
## Basis ##
ENV ENV=prod \
    PORT=8080 \
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    RUNTIME_DEVICE_DOCKER=${RUNTIME_DEVICE} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_ROCM_DOCKER_VER=${USE_ROCM_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL}

ENV DOCKER=true

ENV OLLAMA_MODELS=/var/lib/ollama

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

ENV PATH="/app/.venv/bin:$PATH"

FROM build

ARG USE_OLLAMA

RUN <<EOF
if [["${USE_OLLAMA}" == 'true']]; then
    echo "Installing ollama"
    curl -fsSL https://ollama.com/install.sh | sh
fi
EOF

EXPOSE 8080
HEALTHCHECK --interval=60s --start-period=60s CMD curl --silent --fail http://localhost:8080/health | jq -ne 'input.status == true' || exit 1

CMD [ "bash", "backend/start.sh"]
