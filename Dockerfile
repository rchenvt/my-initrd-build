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

# 4. Manual Injection (Bypass the Feature System)
RUN KVER=$(ls /lib/modules | head -n 1) && \
    # Create the destination subdirectories in the base template
    mkdir -p /build/base/lib/modules/$KVER/kernel/drivers/mfd/ \
             /build/base/lib/modules/$KVER/kernel/drivers/clk/ \
             /build/base/lib/modules/$KVER/kernel/drivers/rtc/ \
             /build/base/lib/modules/$KVER/kernel/drivers/i2c/busses/ && \
    # Manually copy the .ko.gz files from the container's /lib/modules to the template
    find /lib/modules/$KVER/ -name "rk8xx*" -exec cp {} /build/base/lib/modules/$KVER/kernel/drivers/mfd/ \; && \
    find /lib/modules/$KVER/ -name "clk-rk808*" -exec cp {} /build/base/lib/modules/$KVER/kernel/drivers/clk/ \; && \
    find /lib/modules/$KVER/ -name "rtc-rk808*" -exec cp {} /build/base/lib/modules/$KVER/kernel/drivers/rtc/ \; && \
    find /lib/modules/$KVER/ -name "i2c-rk3x*" -exec cp {} /build/base/lib/modules/$KVER/kernel/drivers/i2c/busses/ \; && \
    # Run depmod on the base directory to register these new files
    depmod -b /build/base $KVER

# 5. Build and Wrap
RUN KVER=$(ls /lib/modules | head -n 1) && \
    mkdir -p /build/base/boot && \
    # mkinitfs now sees the modules as "already present" in the base
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
