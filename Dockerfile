FROM --platform=linux/arm64 alpine:latest

# 1. Install tools
RUN apk add --no-cache mkinitfs squashfs-tools cpio gzip wget u-boot-tools

WORKDIR /build

# 2. Download and Extract (6.18.7-lts)
ARG REL=v3.23
ARG VER=3.23.3
RUN wget https://dl-cdn.alpinelinux.org/alpine/${REL}/releases/aarch64/alpine-uboot-${VER}-aarch64.tar.gz && \
    tar -xzf alpine-uboot-${VER}-aarch64.tar.gz

# 3. Setup workspace: extract original initramfs and modules
RUN mkdir base && \
    zcat boot/initramfs-lts | cpio -idmv -D base && \
    unsquashfs -f -d /lib boot/modloop-lts

# 4. Force-Inject Rockchip modules into the 'base' feature
RUN KVER=$(ls /lib/modules | head -n 1) && \
    # Create the directory where mkinitfs looks for features
    mkdir -p /etc/mkinitfs/features.d && \
    # Find the actual files and put their paths into the 'base' feature file
    # This forces mkinitfs to include them when -F base is used
    find /lib/modules/$KVER/ -name "rk8xx*" >> /etc/mkinitfs/features.d/base.modules && \
    find /lib/modules/$KVER/ -name "rk808*" >> /etc/mkinitfs/features.d/base.modules && \
    find /lib/modules/$KVER/ -name "i2c-rk3x*" >> /etc/mkinitfs/features.d/base.modules

# 5. Build and Wrap
RUN KVER=$(ls /lib/modules | head -n 1) && \
    echo "Building for $KVER" && \
    mkdir -p /build/base/lib/modules/$KVER /build/base/boot && \
    # We only need -F base now because we modified the base.modules file
    mkinitfs -b /build/base -F base -k "$KVER" -o initramfs-lts && \
    # Wrap for U-Boot
    mkimage -A arm64 -O linux -T ramdisk -C gzip -n "Alpine-RK8xx" \
            -d /build/base/boot/initramfs-lts /uInitrd && \
    mkimage -A arm64 -O linux -T kernel -C none -a 0x80080000 -e 0x80080000 \
            -n "Kernel" -d boot/vmlinuz-lts /uImage && \
    cp /build/base/boot/initramfs-lts /initramfs-lts
# 6. Verification (Flexible grep)
RUN dd if=/uInitrd bs=64 skip=1 | zcat | cpio -it | grep -E "rk8|rk3x" && \
    echo "SUCCESS: Rockchip modules verified in uInitrd."

CMD ["sh", "-c", "cp /uImage /uInitrd /initramfs-lts /out/"]
