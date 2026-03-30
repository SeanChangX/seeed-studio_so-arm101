# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=huggingface/lerobot-cpu:latest
FROM ${BASE_IMAGE}

ARG SEEED_LEROBOT_REF=0f392484458cb5ebca0310c0c4c47390a31c80ed
ARG SEEED_HF_HUB_VERSION=0.35.3
ARG SEEED_TRANSFORMERS_VERSION=4.57.1
ARG ENABLE_ROS2_HUMBLE=0

ENV PATH=/lerobot/.venv/bin:${PATH} \
    PYTHONUNBUFFERED=1

USER root

# Keep a stable application user across different base images.
RUN id -u user_lerobot >/dev/null 2>&1 || useradd -m -s /bin/bash user_lerobot \
    && mkdir -p /home/user_lerobot /lerobot \
    && chown -R user_lerobot:user_lerobot /home/user_lerobot /lerobot

RUN if [ "${ENABLE_ROS2_HUMBLE}" = "1" ]; then \
      apt-get update \
      && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        gnupg \
        lsb-release \
        python3-colcon-common-extensions \
        python3-pip \
        python3-rosdep \
        python3-venv \
        python3-vcstool \
        ros-dev-tools \
        ros-humble-rmw-cyclonedds-cpp \
      && rm -rf /var/lib/apt/lists/* \
      && (rosdep init || true); \
    fi

USER user_lerobot

WORKDIR /home/user_lerobot

RUN if [ ! -x /lerobot/.venv/bin/python ]; then \
      python3 -m venv /lerobot/.venv; \
    fi \
    && if ! /lerobot/.venv/bin/python -m pip --version >/dev/null 2>&1; then \
         /lerobot/.venv/bin/python -m ensurepip --upgrade; \
       fi \
    && /lerobot/.venv/bin/python -m pip install --no-cache-dir --upgrade pip \
    && /lerobot/.venv/bin/python -m pip install --no-cache-dir uv catkin_pkg

RUN --mount=type=cache,target=/home/user_lerobot/.cache/uv,uid=1000,gid=1000,mode=0755 \
    git clone https://github.com/Seeed-Projects/lerobot.git lerobot-seeed \
    && cd lerobot-seeed \
    && git checkout ${SEEED_LEROBOT_REF} \
    && export UV_HTTP_TIMEOUT=600 UV_HTTP_RETRIES=10 \
    && for attempt in 1 2 3; do \
         /lerobot/.venv/bin/uv pip install -e ".[feetech,transformers-dep]" \
         && /lerobot/.venv/bin/uv pip install \
           "huggingface-hub[hf-transfer,cli]==${SEEED_HF_HUB_VERSION}" \
           "transformers==${SEEED_TRANSFORMERS_VERSION}" \
         && break; \
         if [ "${attempt}" -eq 3 ]; then \
           echo "uv dependency install failed after ${attempt} attempts" >&2; \
           exit 1; \
         fi; \
         echo "uv dependency install failed (attempt ${attempt}/3), retrying in 15s..." >&2; \
         sleep 15; \
       done

RUN cat <<'EOF' >> /home/user_lerobot/.bashrc
# shell colors
export TERM=${TERM:-xterm-256color}
export COLORTERM=truecolor

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b)"
fi

alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias grep='grep --color=auto'

if [ -f /opt/ros/humble/setup.bash ]; then
  source /opt/ros/humble/setup.bash
  export ROS_DISTRO=humble
  export ROS_VERSION=2
  export RMW_IMPLEMENTATION=${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}
fi

PS1='\[\e[38;5;45m\]\u\[\e[0m\]@\[\e[38;5;220m\]\h\[\e[0m\]:\[\e[38;5;111m\]\w\[\e[0m\]\$ '
EOF

WORKDIR /workspace
CMD ["/bin/bash"]
