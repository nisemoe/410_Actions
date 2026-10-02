# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

BOARD:=msm89xx
BOARDNAME:=Boards based on Snapdragon 210/410/615 chipsets
FEATURES:=ext4 usb usbgadget gpio fpu rootfs-part boot-part squashfs testing-kernel
SUBTARGETS:=msm8916

KERNEL_PATCHVER:=6.18
# 主线测试内核（opt-in）：只有 .config 里 CONFIG_TESTING_KERNEL=y 时才生效，
# 6.18 的既有机型配置不受影响。
#   版本与下载规则见 target/linux/generic/kernel-7.3
#   目标配置见 config-7.3，补丁集见 patches-7.3
KERNEL_TESTING_PATCHVER:=7.3

define Target/Description
	Build firmware images for various Snapdragon 210/410/615 based devices
endef

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += partx-utils e2fsprogs mkf2fs kmod-fs-f2fs
DEFAULT_PACKAGES += kmod-usb-chipidea kmod-usb-gadget-eth
DEFAULT_PACKAGES += kmod-wcn36xx kmod-rproc-wcnss
DEFAULT_PACKAGES += kmod-rpmsg-wwan-ctrl kmod-bam-dmux kmod-qcom-rproc-modem
DEFAULT_PACKAGES += rmtfs

KERNELNAME:=Image

$(eval $(call BuildTarget))
