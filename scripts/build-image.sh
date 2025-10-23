#!/bin/bash
set -ex

# --- Configuration ---
BASE_URL=""
OUTPUT_PATH=""

# --- Argument Parsing ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --base-url) BASE_URL="$2"; shift ;;
        --output) OUTPUT_PATH="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

if [ -z "$BASE_URL" ] || [ -z "$OUTPUT_PATH" ]; then
    echo "Usage: $0 --base-url <URL> --output <PATH>"
    exit 1
fi

# --- Main Script ---
WORKDIR=$(mktemp -d)
trap 'sudo umount -lR ${WORKDIR}/mnt || true; rm -rf ${WORKDIR}' EXIT

echo "Downloading base image from ${BASE_URL}..."
curl -L "${BASE_URL}" -o "${WORKDIR}/base.img.xz"
xz -d "${WORKDIR}/base.img.xz"
BASE_IMAGE="${WORKDIR}/base.img"

echo "Resizing image to 8G..."
truncate -s 8G "${BASE_IMAGE}"
parted "${BASE_IMAGE}" --script resizepart 2 100%

echo "Mounting root partition..."
mkdir -p "${WORKDIR}/mnt"
OFFSET=$(parted "${BASE_IMAGE}" unit B print | grep -oE '^[[:space:]]*2[[:space:]]+[0-9]+B' | awk '{print $2}' | tr -d 'B')
sudo mount -o offset="${OFFSET}" "${BASE_IMAGE}" "${WORKDIR}/mnt"

echo "Copying repository rootfs into image..."
sudo rsync -a ./rootfs/ "${WORKDIR}/mnt/"

echo "Setting up chroot environment..."
sudo cp /usr/bin/qemu-aarch64-static "${WORKDIR}/mnt/usr/bin/"

# --- Chroot Operations ---
echo "Running commands inside the chroot..."
sudo chroot "${WORKDIR}/mnt" /bin/bash <<EOF
set -ex

# Mount pseudo-filesystems
mount -t proc none /proc
mount -t sysfs none /sys
mount -t devpts none /dev/pts

export DEBIAN_FRONTEND=noninteractive

# Update and install dependencies
apt-get update
apt-get install -y python3 python3-pip git

# Make the first-boot script executable
chmod +x /usr/local/bin/paka-first-boot.sh

# Enable systemd services
systemctl enable paka-first-boot.service
systemctl enable paka-app.service

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

# Unmount pseudo-filesystems
umount /proc /sys /dev/pts
EOF
# --- End of Chroot ---

echo "Chroot setup complete."

echo "Moving final image to ${OUTPUT_PATH}..."
mv "${BASE_IMAGE}" "${OUTPUT_PATH}"

echo "Build finished successfully!"