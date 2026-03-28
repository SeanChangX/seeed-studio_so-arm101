# SO-ARM101 LeRobot Docker

This setup provides a Docker-based deployment for `Seeed SO-100/SO-101 + LeRobot`, designed to be plug-and-play and avoid rebuilding the stack from scratch.

- Uses official base images: `huggingface/lerobot-cpu` / `huggingface/lerobot-gpu`
- Adds the Seeed wiki recommended fork: `Seeed-Projects/lerobot` (with `.[feetech]`)
- Mounts `/dev`, cache directories, and workspace by default

## 1) Requirements

- Docker Engine + Docker Compose plugin
- For GPU: NVIDIA Driver + NVIDIA Container Toolkit

## 2) Quick Start

Create workspace and cache directories:

```bash
mkdir -p workspace cache/hf cache/torch cache/triton
```

CPU:

```bash
./scripts/lerobot-docker.sh shell cpu
```

GPU:

```bash
./scripts/lerobot-docker.sh shell gpu
```

## 3) Verify Environment

Run inside the container:

```bash
lerobot-info
python -c "import torch; print('cuda:', torch.cuda.is_available())"
python -c "import lerobot; print('lerobot ok')"
```

## 4) Common Commands

Start in background:

```bash
./scripts/lerobot-docker.sh up cpu
# or
./scripts/lerobot-docker.sh up gpu
```

View logs:

```bash
./scripts/lerobot-docker.sh logs
```

Stop:

```bash
./scripts/lerobot-docker.sh down
```

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
  - Then run `./scripts/lerobot-docker.sh shell gpu`
