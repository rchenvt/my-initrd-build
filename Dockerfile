FROM --platform=linux/arm64 alpine:latest

# 1. Install tools
RUN apk add --no-cache mkinitfs squashfs-tools cpio gzip wget u-boot-tools

WORKDIR /build

# 2. Download and Extract (6.18.7-lts)
ARG REL=v3.23
ARG VER=3.23.3
RUN wget https://dl-cdn.alpinelinux.org{REL}/releases/aarch64/alpine-uboot-${VER}-aarch64.tar.gz && \
    tar -xzf alpine-uboot-${VER}-aarch64.tar.gz

# 3. Setup workspace: extract original initramfs and modules
RUN mkdir base && \
    zcat boot/initramfs-lts | cpio -idmv -D base && \
    unsquashfs -f -d /lib boot/modloop-lts

# 4. Force-Inject Rockchip modules
# We list the exact .ko.gz paths to ensure mkinitfs cannot miss them
RUN KVER=$(ls /lib/modules | head -n 1) && \
    mkdir -p /etc/mkinitfs/features.d && \
    find /lib/modules/$KVER/kernel/drivers/mfd/ -name "rk8xx*" > /etc/mkinitfs/features.d/rk8xx.modules && \
    find /lib/modules/$KVER/kernel/drivers/clk/ -name "clk-rk808*" >> /etc/mkinitfs/features.d/rk8xx.modules && \
    find /lib/modules/$KVER/kernel/drivers/rtc/ -name "rtc-rk808*" >> /etc/mkinitfs/features.d/rk8xx.modules && \
    find /lib/modules/$KVER/kernel/drivers/i2c/busses/ -name "i2c-rk3x*" >> /etc/mkinitfs/features.d/rk8xx.modules

# 5. Build and Wrap
RUN KVER=$(ls /lib/modules | head -n 1) && \
    mkdir -p /build/base/lib/modules/$KVER /build/base/boot && \
    # We pass "rk8xx" to -F so it loads our custom feature file
    mkinitfs -b /build/base -F "base rk8xx" -k "$KVER" -o initramfs-lts && \
    mkimage -A arm64 -O linux -T ramdisk -C gzip -n "Alpine-RK8xx" \
            -d /build/base/boot/initramfs-lts /uInitrd && \
    mkimage -A arm64 -O linux -T kernel -C none -a 0x80080000 -e 0x80080000 \
            -n "Kernel" -d boot/vmlinuz-lts /uImage && \
    cp /build/base/boot/initramfs-lts /initramfs-lts

# 6. Verification (Flexible grep)
RUN dd if=/uInitrd bs=64 skip=1 | zcat | cpio -it | grep -E "rk8|rk3x" && \
    echo "SUCCESS: Rockchip modules verified in uInitrd."

CMD ["sh", "-c", "cp /uImage /uInitrd /initramfs-lts /out/"]
