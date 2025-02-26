#!/usr/bin/env python

import os
import tiktoken
from sentence_transformers import SentenceTransformer
from faster_whisper import WhisperModel

print("Fetching embedding model")
SentenceTransformer(os.environ["RAG_EMBEDDING_MODEL"], device="cpu", trust_remote_code=True)
print("Fetching whisper model")
WhisperModel(
    os.environ["WHISPER_MODEL"],
    device="cpu",
    compute_type="int8",
    download_root=os.environ["WHISPER_MODEL_DIR"],
)
print("Fetching tiktoken model")
tiktoken.get_encoding(os.environ["TIKTOKEN_ENCODING_NAME"])
