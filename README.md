# SO-ARM101 LeRobot Docker

This setup provides a Docker-based deployment for `Seeed SO-100/SO-101 + LeRobot`, designed to be plug-and-play and avoid rebuilding the stack from scratch.

- Uses official base images: `huggingface/lerobot-cpu` / `huggingface/lerobot-gpu`
- Adds the Seeed wiki recommended fork: `Seeed-Projects/lerobot` (with `.[feetech]`)
- Optional ROS2 Humble profiles for `so101_ros2` integration
- Mounts `/dev`, cache directories, and workspace by default

Note: `humble` / `humble-gpu` profiles use `ros:humble-ros-base-jammy` as base image to keep ROS2 package compatibility.

## 1) Requirements

- Docker Engine + Docker Compose plugin
- For GPU: NVIDIA Driver + NVIDIA Container Toolkit

## 2) Quick Start

Copy environment template (optional):

```bash
cp docker/.env.example docker/.env
```

Start Command Deck:

```bash
./soarmctl docker
```

Same entry via `scripts/`:

```bash
./scripts/lerobot-docker.sh
```

Other helpers: run `./soarmctl help` (for example `./soarmctl usb` for USB serial setup).

Recommended first-time flow in Command Deck:

1. Start Command Deck and choose profile once
2. Run `quickstart`

Profile is kept for the whole session. Use `switch-profile` only when needed.
`quickstart` is one-flow by profile:

- `cpu/gpu`: build + shell
- `humble/humble-gpu`: build + ros2-setup + shell

Quickstart build policy:

- if target image already exists, `quickstart` skips build
- if target image does not exist locally, `quickstart` pulls from `IMAGE_NAME` first
- if primary pull fails, `quickstart` tries `IMAGE_FALLBACK_NAME` (Docker Hub fallback)
- use `build` action to force rebuild image

## 3) Verify Environment

Run inside the container:

```bash
lerobot-info
python -c "import torch; print('cuda:', torch.cuda.is_available())"
python -c "import lerobot; print('lerobot ok')"
```

If profile is `humble` or `humble-gpu`, also verify:

```bash
python -c "import rclpy; print('rclpy ok')"
ros2 topic list
colcon --help | head -n 2
```

## 4) Command Deck Actions

- `quickstart`: one-flow start (auto-skip build when image exists)
- `build`: build image
- `up`: start container
- `shell`: open interactive shell
- `ros2-setup`: sync `so101_ros2` (default: `SeanChangX/so101_ros2@seeed-so-arm101-base`), install rosdep packages, and run `colcon build`
- `soarm-usb-setup`: detect SO-ARM tty by replug flow and run `chmod 666` automatically
- `logs`: stream logs
- `down`: stop container
- `switch-profile`: change active profile for the rest of the session

Notes:

- `ros2-setup` is available only when active profile is `humble` or `humble-gpu`
- `quickstart` works on all profiles
- `up` / `shell` automatically run `xhost +local:docker` when `DISPLAY` is set
- override source with `SO101_ROS2_REPO_URL` / `SO101_ROS2_REPO_BRANCH` if needed

## 5) Mapping to Seeed Wiki

The core setup steps in the Seeed wiki are:

- clone `Seeed-Projects/lerobot`
- install `pip install -e ".[feetech]"`

Both are already done during image build, so after entering the container you can directly run data collection, training, and evaluation commands.

## 6) Troubleshooting

- Serial port not found (for example `/dev/ttyACM0`):
  - Confirm device exists on host: `ls /dev/ttyACM*`
  - `/dev` is already mounted in compose; if permission is still denied, run on host: `sudo chmod 666 /dev/ttyACM*`
- GPU not detected:
  - Check `nvidia-smi` on host first
  - Then run action `shell` with profile `gpu`

## 7) Teleoperate Example (SO101)

```bash
lerobot-teleoperate \
    --robot.type=so101_follower \
    --robot.port=/dev/ttyACM0 \
    --robot.id=my_awesome_follower_arm \
    --teleop.type=so101_leader \
    --teleop.port=/dev/ttyACM1 \
    --teleop.id=my_awesome_leader_arm
```

## 8) Start ROS2 Humble Integration (`so101_ros2`)

Open Command Deck and choose:

1. choose profile `humble` (or `humble-gpu`) once
2. `ros2-setup`
3. `shell`
4. inside container: `source /workspace/ros2_ws/install/local_setup.bash`

Then validate:

```bash
ros2 pkg list | grep so101
```

## 9) Common ROS2 Flows (Humble / Humble-GPU)

Always source ROS first in each new shell:

```bash
source /opt/ros/humble/setup.bash
source /workspace/ros2_ws/install/local_setup.bash
```

Full teleop launch (human leader + follower, RViz + cameras):

```bash
ros2 launch so101_bringup so101_teleoperate.launch.py \
  teleop_mode:=real \
  expert:=human \
  display:=true \
  enable_cameras:=true
```

Headless teleop launch (no RViz, no cameras):

```bash
ros2 launch so101_bringup so101_teleoperate.launch.py \
  teleop_mode:=real \
  expert:=human \
  display:=false \
  enable_cameras:=false
```

If you do not have side RealSense yet, keep only USB claw camera in
`so101_bringup/config/so101_cameras.yaml` and remove/comment the `cam_side` entry.
Then rebuild:

```bash
cd /workspace/ros2_ws
colcon build --packages-select so101_bringup
source /workspace/ros2_ws/install/local_setup.bash
```

When switching profile (`humble` <-> `humble-gpu`), rebuild ROS packages once in that profile:

```bash
cd /workspace/ros2_ws
colcon build --packages-select so101_ros2_bridge so101_bringup so101_controller so101_teleop
source /workspace/ros2_ws/install/local_setup.bash
```

Quick runtime checks:

```bash
ros2 param get /follower/so101_follower_interface max_relative_target
ros2 topic hz /leader/joint_states
ros2 topic hz /follower/joint_states_raw
```
