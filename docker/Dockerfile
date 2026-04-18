# syntax=docker/dockerfile:1.22

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
      && ros_runtime_pkgs="\
        ros-humble-control-msgs \
        ros-humble-control-toolbox \
        ros-humble-controller-manager \
        ros-humble-joint-state-publisher \
        ros-humble-joint-state-publisher-gui \
        ros-humble-launch-param-builder \
        ros-humble-moveit \
        ros-humble-moveit-common \
        ros-humble-moveit-configs-utils \
        ros-humble-moveit-core \
        ros-humble-moveit-msgs \
        ros-humble-moveit-ros-move-group \
        ros-humble-moveit-ros-planning \
        ros-humble-moveit-ros-planning-interface \
        ros-humble-moveit-ros-visualization \
        ros-humble-moveit-servo \
        ros-humble-realsense2-camera \
        ros-humble-robot-state-publisher \
        ros-humble-ros2-control \
        ros-humble-ros2-controllers \
        ros-humble-rviz2 \
        ros-humble-rviz-common \
        ros-humble-rviz-default-plugins \
        ros-humble-tf2-eigen \
        ros-humble-tf2-ros \
        ros-humble-rosbridge-suite \
        ros-humble-usb-cam \
        ros-humble-xacro" \
      && installable_ros_runtime_pkgs="" \
      && for pkg in ${ros_runtime_pkgs}; do \
           if apt-cache show "${pkg}" >/dev/null 2>&1; then \
             installable_ros_runtime_pkgs="${installable_ros_runtime_pkgs} ${pkg}"; \
           else \
             echo "Skipping unavailable ROS package: ${pkg}"; \
           fi; \
         done \
      && if [ -n "${installable_ros_runtime_pkgs# }" ]; then \
           apt-get install -y --no-install-recommends ${installable_ros_runtime_pkgs}; \
         fi \
      && rm -rf /var/lib/apt/lists/* \
      && (rosdep init || true); \
    fi

USER user_lerobot

WORKDIR /home/user_lerobot

# ROS2 apt packages install Python modules into system site-packages; expose
# them only for ROS2-enabled images to keep the default LeRobot venv isolated.
RUN if [ ! -x /lerobot/.venv/bin/python ]; then \
      if [ "${ENABLE_ROS2_HUMBLE}" = "1" ]; then \
        python3 -m venv /lerobot/.venv --system-site-packages; \
      else \
        python3 -m venv /lerobot/.venv; \
      fi; \
    elif [ "${ENABLE_ROS2_HUMBLE}" = "1" ]; then \
      sed -i 's/include-system-site-packages = false/include-system-site-packages = true/' \
        /lerobot/.venv/pyvenv.cfg || true; \
    fi \
    && if ! /lerobot/.venv/bin/python -m pip --version >/dev/null 2>&1; then \
         /lerobot/.venv/bin/python -m ensurepip --upgrade; \
       fi \
    && /lerobot/.venv/bin/python -m pip install --no-cache-dir --upgrade pip \
    && /lerobot/.venv/bin/python -m pip install --no-cache-dir uv catkin_pkg ikpy tornado \
    && /lerobot/.venv/bin/python -m pip install --no-cache-dir 'teleop[utils]' matplotlib

RUN --mount=type=cache,target=/home/user_lerobot/.cache/uv,uid=1000,gid=1000,mode=0755 \
    git clone https://github.com/Seeed-Projects/lerobot.git lerobot-seeed \
    && cd lerobot-seeed \
    && git checkout ${SEEED_LEROBOT_REF} \
    && if [ ! -f src/lerobot/robots/so101_follower.py ]; then \
         printf '%s\n' \
           'from lerobot.robots.so_follower.so_follower import SOFollower as SO101Follower' \
           'from lerobot.robots.so_follower.config_so_follower import SOFollowerConfig as SO101FollowerConfig' \
           '' \
           '__all__ = ["SO101Follower", "SO101FollowerConfig"]' \
           > src/lerobot/robots/so101_follower.py; \
       fi \
    && if [ ! -f src/lerobot/teleoperators/so101_leader.py ]; then \
         printf '%s\n' \
           'from lerobot.teleoperators.so_leader.so_leader import SOLeader as SO101Leader' \
           'from lerobot.teleoperators.so_leader.config_so_leader import SOLeaderConfig as SO101LeaderConfig' \
           '' \
           '__all__ = ["SO101Leader", "SO101LeaderConfig"]' \
           > src/lerobot/teleoperators/so101_leader.py; \
       fi \
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

if [ -z "${LECONDA_SITE_PACKAGES:-}" ] && [ -d /home/user_lerobot/lerobot-seeed/src ]; then
  export LECONDA_SITE_PACKAGES=/home/user_lerobot/lerobot-seeed/src:/lerobot/.venv/lib/python3.10/site-packages
fi

if [ -z "${PYTHONPATH:-}" ]; then
  export PYTHONPATH=/home/user_lerobot/lerobot-seeed/src:/lerobot/.venv/lib/python3.10/site-packages
fi

# ROS2 workspace setup (colcon install space)
if [ -f /workspace/ros2_ws/install/local_setup.bash ]; then
  source /workspace/ros2_ws/install/local_setup.bash
fi

PS1='\[\e[38;5;45m\]\u\[\e[0m\]@\[\e[38;5;220m\]\h\[\e[0m\]:\[\e[38;5;111m\]\w\[\e[0m\]\$ '
EOF

WORKDIR /workspace
CMD ["/bin/bash"]
