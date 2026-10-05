# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk


define Build/Compile
	$(CP) $(LINUX_DIR)/COPYING $(KDIR)/COPYING.linux
endef

### Image scripts ###
define Build/aboot-img
	mkbootimg \
	  --kernel $@ \
	  --ramdisk /dev/null \
	  --cmdline $(CMDLINE) \
	  -o $@.new
	mv $@.new $@
endef

define Build/sparse-img
	img2simg $@ $@.new
	mv $@.new $@
endef

### Devices ###
define Device/Default
	PROFILES := Default
	KERNEL = kernel-bin | gzip | append-dtb | aboot-img
	IMAGES := boot.img system.img rootfs.img sysupgrade.bin
	# NO append-metadata here: the JSON trailer makes the image size a
	# non-multiple of 4096, which breaks "fastboot -S <n> flash" (it
	# sparsifies the raw image on the fly and rejects the partial block).
	IMAGE/boot.img := append-kernel
	IMAGE/system.img := append-rootfs
	# rootfs.img is the Android sparse variant - same format as the
	# reference firmware, drop-in for "fastboot -S 200m flash rootfs".
	IMAGE/rootfs.img := append-rootfs | sparse-img
	IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
	DEVICE_DTS_DIR := $(DTS_DIR)/qcom
	DEVICE_DTS = $$(SOC)-$(lastword $(subst _, ,$(1)))
	CMDLINE := "earlycon console=ttyMSM0,115200 rw"
endef

include $(SUBTARGET).mk

$(eval $(call BuildImage))