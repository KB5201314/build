COMPILE_NS_USER ?= 64
override COMPILE_NS_KERNEL := 64
COMPILE_S_USER ?= 64
COMPILE_S_KERNEL ?= 64

include common.mk

DEBUG ?= 1

# Do not leave a partially downloaded binary in case wget fails midway
.DELETE_ON_ERROR:

################################################################################
# Paths to git projects and various binaries
################################################################################
TF_A_PATH		?= $(ROOT)/trusted-firmware-a
BINARIES_PATH		?= $(ROOT)/out
UBOOT_PATH		?= $(ROOT)/u-boot
UBOOT_BIN		?= $(UBOOT_PATH)/u-boot.bin
ROOT_IMG 		?= $(ROOT)/out-br/images/rootfs.ext2
BOOT_IMG		?= $(ROOT)/out/boot.ext2
RKDEVELOPTOOL_PATH	?= $(ROOT)/rkdeveloptool
RKDEVELOPTOOL_BIN	?= $(RKDEVELOPTOOL_PATH)/rkdeveloptool

LINUX_MODULES ?= n

BR2_TARGET_ROOTFS_CPIO = n
BR2_TARGET_ROOTFS_CPIO_GZIP = n
BR2_TARGET_ROOTFS_EXT2 = y
BR2_TARGET_GENERIC_GETTY_PORT = ttyS2
ifeq ($(LINUX_MODULES),y)
# If modules are installed...
# ...enable automatic device detection and driver loading
BR2_ROOTFS_DEVICE_CREATION_DYNAMIC_EUDEV = y
# ...and configure eth0 automatically based on ifup helpers
BR2_PACKAGE_IFUPDOWN_SCRIPTS = y
BR2_SYSTEM_DHCP = eth0
# An image with module takes more space
BR2_TARGET_ROOTFS_EXT2_SIZE = 256M
# Enable SSH daemon for remote login
BR2_PACKAGE_OPENSSH = y
BR2_PACKAGE_OPENSSH_SERVER = y
BR2_ROOTFS_POST_BUILD_SCRIPT = $(ROOT)/build/br-ext/board/king3399/post-build.sh
else
BR2_TARGET_ROOTFS_EXT2_SIZE = 112M
endif

################################################################################
# Targets
################################################################################

all: buildroot boot-img

clean: buildroot-clean

include toolchain.mk

################################################################################
# Arm Trusted Firmware-A
################################################################################
TF_A_EXPORTS ?= CROSS_COMPILE="$(CCACHE)$(AARCH64_CROSS_COMPILE)" \
		M0_CROSS_COMPILE="$(CCACHE)$(AARCH32_CROSS_COMPILE)"

TF_A_DEBUG ?= $(DEBUG)
ifeq ($(TF_A_DEBUG),0)
TF_A_LOGLVL ?= 30
TF_A_OUT = $(TF_A_PATH)/build/rk3399/release
else
TF_A_LOGLVL ?= 40
TF_A_OUT = $(TF_A_PATH)/build/rk3399/debug
endif

TF_A_FLAGS ?= ARCH=aarch64 PLAT=rk3399 SPD=opteed DEBUG=$(TF_A_DEBUG) \
	      LOG_LEVEL=$(TF_A_LOGLVL)

.PHONY: tfa
tfa:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) bl31

.PHONY: tfa-clean
tfa-clean:
	$(TF_A_EXPORTS) $(MAKE) -C $(TF_A_PATH) $(TF_A_FLAGS) clean

clean: tfa-clean

################################################################################
# U-Boot
################################################################################
# TODO: fix this
UBOOT_DEFCONFIG_FILES := $(UBOOT_PATH)/configs/rock-pi-4-rk3399_defconfig \
			 $(ROOT)/build/kconfigs/u-boot_rockpi4.conf

UBOOT_FLAGS ?= CROSS_COMPILE=$(CROSS_COMPILE_NS_KERNEL) \
	       CC=$(CROSS_COMPILE_NS_KERNEL)gcc \
	       HOSTCC="$(CCACHE) gcc"

UBOOT_EXPORTS ?= BL31=$(TF_A_OUT)/bl31/bl31.elf TEE=$(OPTEE_OS_BIN)

u-boot-defconfig: $(UBOOT_PATH)/.config

$(UBOOT_PATH)/.config: $(UBOOT_DEFCONFIG_FILES)
	cd $(UBOOT_PATH) && \
                scripts/kconfig/merge_config.sh $(UBOOT_DEFCONFIG_FILES)

.PHONY: u-boot-defconfig

.PHONY: u-boot
u-boot: $(UBOOT_PATH)/.config optee-os tfa
	$(UBOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) $(UBOOT_FLAGS)

.PHONY: u-boot-clean
u-boot-clean:
	$(UBOOT_EXPORTS) $(MAKE) -C $(UBOOT_PATH) $(UBOOT_FLAGS) distclean

clean: u-boot-clean

################################################################################
# Linux kernel
################################################################################
LINUX_DEFCONFIG_COMMON_ARCH ?= arm64
LINUX_DEFCONFIG_COMMON_FILES ?= $(LINUX_PATH)/arch/arm64/configs/king3399_defconfig \
				$(CURDIR)/kconfigs/king3399.conf

.PHONY: linux-defconfig
linux-defconfig: $(LINUX_PATH)/.config

LINUX_COMMON_FLAGS += ARCH=arm64 Image rockchip/rk3399-king3399.dtb \
			$(if $(filter y,$(LINUX_MODULES)),modules)

.PHONY: linux
linux: linux-common
ifeq ($(LINUX_MODULES),y)
	$(MAKE) -C $(LINUX_PATH) ARCH=arm64 modules_install \
		INSTALL_MOD_PATH=$(BINARIES_PATH)/modules
endif

$(LINUX_PATH)/arch/arm64/boot/Image: linux

.PHONY: linux-defconfig-clean
linux-defconfig-clean: linux-defconfig-clean-common

LINUX_CLEAN_COMMON_FLAGS += ARCH=arm64

.PHONY: linux-clean
linux-clean: linux-clean-common

LINUX_CLEANER_COMMON_FLAGS += ARCH=arm64

.PHONY: linux-cleaner
linux-cleaner: linux-cleaner-common

################################################################################
# OP-TEE
################################################################################
OPTEE_OS_PLATFORM = rockchip-rk3399
OPTEE_OS_COMMON_FLAGS += CFG_ENABLE_EMBEDDED_TESTS=y

.PHONY: optee-os
optee-os: optee-os-common

.PHONY: optee-os-clean
optee-os-clean: optee-os-clean-common

clean: optee-os-clean

################################################################################
# Boot partition (boot.ext2)
################################################################################

.PHONY: $(BOOT_IMG)
$(BOOT_IMG): $(LINUX_PATH)/arch/arm64/boot/Image
	mkdir -p $(BINARIES_PATH)
	rm -f $(BOOT_IMG)

	rm -rf $(BINARIES_PATH)/boot
	mkdir -p $(BINARIES_PATH)/boot
	cp $(LINUX_PATH)/arch/arm64/boot/Image $(BINARIES_PATH)/boot/Image
	cp $(LINUX_PATH)/arch/arm64/boot/dts/rockchip/rk3399-king3399.dtb $(BINARIES_PATH)/boot/rk3399.dtb
	mkdir $(BINARIES_PATH)/boot/extlinux
	printf "label rockchip-kernel-4.4\n    kernel /Image\n    fdt /rk3399.dtb\n    append earlycon=uart8250,mmio32,0xff1a0000 console=ttyS2,115200 root=PARTLABEL=rootfs rw rootwait rootfstype=ext4 init=/sbin/init\n" > $(BINARIES_PATH)/boot/extlinux/extlinux.conf

# TODO: fix this
ifeq ($(LINUX_MODULES),y)
	find $(BINARIES_PATH)/modules -type f | while read f; do cp -a $$f $(BINARIES_PATH)/boot/$$(echo $$f | sed s@$(BINARIES_PATH)/modules@@); done
endif
	genext2fs -b 65536 -B 1024 -d $(BINARIES_PATH)/boot/ -i 8192 -U $(BOOT_IMG)

.PHONY: boot-img
boot-img: $(BOOT_IMG)

.PHONY: boot-img-clean
boot-img-clean:
	rm -f $(BOOT_IMG)

clean: boot-img-clean

################################################################################
# rkdeveloptool
################################################################################

$(RKDEVELOPTOOL_PATH)/Makefile:
	cd $(RKDEVELOPTOOL_PATH) && \
		autoreconf -i && \
		./configure CXXFLAGS=-Wno-format-truncation

$(RKDEVELOPTOOL_BIN): $(RKDEVELOPTOOL_PATH)/Makefile
	$(MAKE) -C $(RKDEVELOPTOOL_PATH)

rkdeveloptool: $(RKDEVELOPTOOL_BIN)

rkdeveloptool-clean:
	$(MAKE) -C $(RKDEVELOPTOOL_PATH) clean

rkdeveloptool-distclean:
	$(MAKE) -C $(RKDEVELOPTOOL_PATH) clean

clean: rkdeveloptool-clean

$(LOADER_BIN):
	cd $(BINARIES_PATH) && \
		wget https://dl.radxa.com/rockpi/images/loader/$(notdir $(LOADER_BIN))

################################################################################
# Flash the image via USB onto the onboard eMMC
################################################################################

define flash-help
	@echo
	@echo "Please connect the board to the computer via a USB cable."
	@echo "The cable must be connected to the upper USB 3 (blue) port."
	@echo "Then press and hold the mask ROM button (first one on the left"
	@echo "under the HDMI connector), apply power and release the button."
	@echo "(More details at https://wiki.radxa.com/Rockpi4/dev/usb-install)"
	@echo
	@read -r -p "Press enter to continue, Ctrl-C to cancel:" dummy
endef

gpt-flash:
	$(call flash-help)
	$(RKDEVELOPTOOL_BIN) gpt $(ROOT)/build/king3399/parameter_linux_distro.txt

boot-img-flash: $(BOOT_IMG) $(RKDEVELOPTOOL_BIN)
	$(call flash-help)
	$(RKDEVELOPTOOL_BIN) wl 0x$$($(RKDEVELOPTOOL_BIN) ppt | dos2unix | egrep ' boot$$' | awk '{ print $$2 }') $(BOOT_IMG)

# TODO: fix this
flash: $(BOOT_IMG) $(LOADER_BIN) $(RKDEVELOPTOOL_BIN)
	$(call flash-help)
	$(RKDEVELOPTOOL_BIN) db $(LOADER_BIN)
	sleep 1
	$(RKDEVELOPTOOL_BIN) wl 0 $(BOOT_IMG)

nuke-emmc: $(LOADER_BIN) $(RKDEVELOPTOOL_BIN)
	@echo
	@echo "** WARNING: this command will make the onboard eMMC unbootable!"
	@echo "It can be used to boot from the SD card again."
	$(call flash-help)
	dd if=/dev/zero of=$(BINARIES_PATH)/zero.img bs=1M count=64
	$(RKDEVELOPTOOL_BIN) db $(LOADER_BIN)
	sleep 1
	$(RKDEVELOPTOOL_BIN) wl 0 $(BINARIES_PATH)/zero.img
