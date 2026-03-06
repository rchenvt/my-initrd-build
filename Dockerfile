FROM --platform=linux/arm64 alpine:latest  

# 1. Install build tools
RUN apk add --no-cache mkinitfs squashfs-tools cpio gzip wget u-boot-tools

WORKDIR /build

# 2. Download Alpine U-Boot release (6.18.7-lts)
ARG REL=v3.23
ARG VER=3.23.3
RUN wget https://dl-cdn.alpinelinux.org/alpine/${REL}/releases/aarch64/alpine-uboot-${VER}-aarch64.tar.gz && \
    tar -xzf alpine-uboot-${VER}-aarch64.tar.gz

# 3. Setup workspace: extract original initramfs and modules
RUN mkdir base && \
    zcat boot/initramfs-lts | cpio -idmv -D base && \
    unsquashfs -d /lib boot/modloop-lts

# 4. Define Rockchip PMIC & Clock features
RUN mkdir -p /etc/mkinitfs/features.d && \
    printf "kernel/drivers/mfd/rk8xx*\nkernel/drivers/clk/clk-rk808*\nkernel/drivers/rtc/rtc-rk808*\nkernel/drivers/i2c/busses/i2c-rk3x*\n" \
    > /etc/mkinitfs/features.d/rk8xx.modules

# 5. Build New Initramfs & Wrap for U-Boot
RUN KVER=$(ls /lib/modules | head -n 1) && \
    # Build the CPIO and a standard initramfs-lts (raw)
    mkinitfs -b /build/base -F "base rk8xx" -k "$KVER" -o /initramfs-lts && \
    # Create the U-Boot uInitrd
    mkimage -A arm64 -O linux -T ramdisk -C gzip -n "Alpine-RK8xx-Initrd" \
            -d /initramfs-lts /uInitrd && \
    # Create the U-Boot uImage from vmlinuz-lts
    mkimage -A arm64 -O linux -T kernel -C none -a 0x80080000 -e 0x80080000 \
            -n "Alpine-RK8xx-Kernel" -d boot/vmlinuz-lts /uImage

# 6. Verification
RUN dd if=/uInitrd bs=64 skip=1 | zcat | cpio -it | grep -E "rk8xx|rk808" && \
    echo "SUCCESS: Modules verified in uInitrd."

# 7. Output all files
CMD cp /uImage /uInitrd /initramfs-lts /out/
