ARG BASE_IMAGE=huggingface/lerobot-cpu:latest
FROM ${BASE_IMAGE}

ARG SEEED_LEROBOT_REF=0f392484458cb5ebca0310c0c4c47390a31c80ed
ARG SEEED_HF_HUB_VERSION=0.35.3
ARG SEEED_TRANSFORMERS_VERSION=4.57.1

ENV PATH=/lerobot/.venv/bin:${PATH} \
    PYTHONUNBUFFERED=1

WORKDIR /home/user_lerobot

RUN git clone https://github.com/Seeed-Projects/lerobot.git lerobot-seeed \
    && cd lerobot-seeed \
    && git checkout ${SEEED_LEROBOT_REF} \
    && uv pip install --no-cache -e ".[feetech,transformers-dep]" \
    && uv pip install --no-cache \
        "huggingface-hub[hf-transfer,cli]==${SEEED_HF_HUB_VERSION}" \
        "transformers==${SEEED_TRANSFORMERS_VERSION}"

WORKDIR /workspace
CMD ["/bin/bash"]
