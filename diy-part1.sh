#!/bin/bash

# msm8916
cp -rf "$GITHUB_WORKSPACE/scripts/msm89xx/target/." target/
cp -rf "$GITHUB_WORKSPACE/scripts/msm89xx/package/." package/
cp -rf "$GITHUB_WORKSPACE/scripts/msm89xx/toolchain/." toolchain/
cp -rf "$GITHUB_WORKSPACE/scripts/msm89xx/feeds.conf.default" feeds.conf.default
# 验证
ls target/linux/msm89xx/Makefile package/kernel/mac80211/patches/ath/*wcn36xx* package/kernel/mac80211/ath.mk toolchain/musl/include/sys/glibc-types.h

# OpenAppFilter
git clone --depth 1 https://github.com/destan19/luci-app-harbor-file.git package/harbor-file

# turboacc：源码由 diy-part2.sh 从 mufeng05/turboacc 拷进 package/（内核 6.18 已验证）。
# 这里不再用 add_turboacc.sh（会打 SFE 内核补丁 953，6.18 上编不进，且与 CAKE 冲突）。

# kenzo
echo 'src-git kenzo https://github.com/kenzok8/openwrt-packages' >> feeds.conf.default

# small
echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default

# ---------------------------------------------------------------------------
# Linux 7.3-rc5（主线测试内核）准备
# target/linux/msm89xx/Makefile 里 KERNEL_TESTING_PATCHVER:=7.3，
# 只有 .config 打开 CONFIG_TESTING_KERNEL=y（见 config/wf2-73.config）时才生效，
# 走 6.18 的机型配置完全不受影响。
# ---------------------------------------------------------------------------
# 注意：不能只依赖脚本开头那条 cp -rf —— 一旦仓库里 patches-7.3 这类**新目录**
# 没被提交推送，Actions 的 checkout 就拿不到，编译会在打补丁阶段炸掉。
# 所以下面每个文件都做"缺失就从仓库源取，再没有就就地用 6.18 生成"的兜底。

WS="${GITHUB_WORKSPACE:-$(cd .. && pwd)}"
K73_SRC="$WS/scripts/msm89xx/target/linux"

# 0) 关键：目标 Makefile 必须声明 testing-kernel + KERNEL_TESTING_PATCHVER:=7.3。
#    缺了它 HAS_TESTING_KERNEL 就不会被 select，defconfig 会把 .config 里的
#    CONFIG_TESTING_KERNEL=y / CONFIG_LINUX_7_3=y 静默删掉 -> 实际编出来是 6.18！
#    所以这里不依赖仓库是否已推送该 Makefile，缺什么就地补什么。
MK=target/linux/msm89xx/Makefile
if [ -f "$MK" ]; then
	sed -i 's/\r$//' "$MK"
	if ! grep -q "KERNEL_TESTING_PATCHVER" "$MK"; then
		sed -i '/^KERNEL_PATCHVER:=/a KERNEL_TESTING_PATCHVER:=7.3' "$MK"
		echo "⚠️ 目标 Makefile 缺 KERNEL_TESTING_PATCHVER，已就地补上 7.3"
	fi
	if ! grep -q "testing-kernel" "$MK"; then
		sed -i 's/^FEATURES:=.*/& testing-kernel/' "$MK"
		echo "⚠️ 目标 Makefile FEATURES 缺 testing-kernel，已就地补上"
	fi
	echo "----- target/linux/msm89xx/Makefile 内核相关行 -----"
	grep -nE "FEATURES|KERNEL_PATCHVER|KERNEL_TESTING_PATCHVER" "$MK" || true
else
	echo "❌ 找不到 target/linux/msm89xx/Makefile"
fi

# 1) generic/kernel-7.3：内核版本号（缺了 kernel-version.mk 会直接 error）
if [ ! -f target/linux/generic/kernel-7.3 ]; then
	if [ -f "$K73_SRC/generic/kernel-7.3" ]; then
		cp -f "$K73_SRC/generic/kernel-7.3" target/linux/generic/kernel-7.3
		echo "✅ 已补回 target/linux/generic/kernel-7.3"
	else
		printf 'LINUX_VERSION-7.3 = -rc5\nLINUX_KERNEL_HASH-7.3-rc5 = skip\n' > target/linux/generic/kernel-7.3
		echo "⚠️ 仓库未带 generic/kernel-7.3，已按 -rc5 现场生成"
	fi
fi

# 1b) 必须有 hash 定义：download.pl 不认 kernel-version.mk 默认的 "x"（会 die -> make download 退出码 2），
#     只认 64 位 sha256 / 32 位 md5 / 字面量 skip。缺了就补 skip。
if [ -f target/linux/generic/kernel-7.3 ]; then
	if ! grep -q "^LINUX_KERNEL_HASH-7.3-rc5" target/linux/generic/kernel-7.3; then
		printf 'LINUX_KERNEL_HASH-7.3-rc5 = skip\n' >> target/linux/generic/kernel-7.3
		echo "⚠️ kernel-7.3 缺 LINUX_KERNEL_HASH 定义，已补 skip（否则 make download 会失败）"
	fi
	echo "----- target/linux/generic/kernel-7.3 生效行 -----"
	grep -E "^(LINUX_VERSION|LINUX_KERNEL_HASH)" target/linux/generic/kernel-7.3 || true
fi

# 2) generic/config-7.3：上游不会为新内核提供，用最新的 config-x.y 复制一份。
#    kconfig 里已不存在/改名的符号会在内核 olddefconfig 阶段自动丢弃或取默认值。
if [ ! -f target/linux/generic/config-7.3 ]; then
	if [ -f "$K73_SRC/generic/config-7.3" ]; then
		cp -f "$K73_SRC/generic/config-7.3" target/linux/generic/config-7.3
		echo "✅ 已补回 target/linux/generic/config-7.3"
	else
		base=$(ls -1 target/linux/generic/config-* 2>/dev/null | grep -E 'config-[0-9]+\.[0-9]+$' | sort -V | tail -1)
		if [ -n "$base" ]; then
			cp -f "$base" target/linux/generic/config-7.3
			echo "✅ 已由 $base 生成 target/linux/generic/config-7.3"
		else
			echo "⚠️ 未找到可用的 generic config-* 作为 config-7.3 模板"
		fi
	fi
fi

# 3) msm89xx/config-7.3
if [ ! -f target/linux/msm89xx/config-7.3 ]; then
	if [ -f "$K73_SRC/msm89xx/config-7.3" ]; then
		cp -f "$K73_SRC/msm89xx/config-7.3" target/linux/msm89xx/config-7.3
		echo "✅ 已补回 target/linux/msm89xx/config-7.3"
	elif [ -f target/linux/msm89xx/config-6.18 ]; then
		cp -f target/linux/msm89xx/config-6.18 target/linux/msm89xx/config-7.3
		echo "⚠️ 仓库未带 msm89xx/config-7.3，已由 config-6.18 就地生成"
	fi
fi

# 4) msm89xx/patches-7.3（目录，最容易漏提交）
if [ ! -d target/linux/msm89xx/patches-7.3 ] || [ -z "$(ls -A target/linux/msm89xx/patches-7.3 2>/dev/null)" ]; then
	if [ -d "$K73_SRC/msm89xx/patches-7.3" ]; then
		mkdir -p target/linux/msm89xx/patches-7.3
		cp -rf "$K73_SRC/msm89xx/patches-7.3/." target/linux/msm89xx/patches-7.3/
		echo "✅ 已补回 target/linux/msm89xx/patches-7.3"
	elif [ -d target/linux/msm89xx/patches-6.18 ]; then
		cp -rf target/linux/msm89xx/patches-6.18 target/linux/msm89xx/patches-7.3
		echo "⚠️ 仓库未带 msm89xx/patches-7.3，已由 patches-6.18 就地生成"
	fi
fi

# 4b) 补丁目录卫生：patches-7.3 下只要混进任何非 .patch 的文件（例如误上传的 "1"），
#     quilt/patch 都会把它当成补丁去应用，然后报
#       patch: **** Only garbage was found in the patch input.
#     整个 target/linux 编译直接红掉，而错误信息里根本看不出是哪个文件。
#     这里在打补丁之前先清一遍，并把删掉的文件名打进日志。
if [ -d target/linux/msm89xx/patches-7.3 ]; then
	junk=$(find target/linux/msm89xx/patches-7.3 -maxdepth 1 -type f ! -name '*.patch' 2>/dev/null)
	if [ -n "$junk" ]; then
		echo "::warning::patches-7.3 中发现非补丁文件，已删除："
		echo "$junk"
		find target/linux/msm89xx/patches-7.3 -maxdepth 1 -type f ! -name '*.patch' -delete
	else
		echo "✅ patches-7.3 目录干净（无非 .patch 文件）"
	fi
	echo "----- patches-7.3 内容 -----"
	ls -1 target/linux/msm89xx/patches-7.3 || true
fi

# 4c) 工具链内核头文件补丁目录。
#     注意：**用户态程序用的是 toolchain 里的内核头文件**（
#     staging_dir/toolchain-*/include），不是 target/linux 下的那份。
#     toolchain/kernel-headers 的 PATCH_DIR 是 ./patches（或 ./patches-<版本>），
#     所以 7.3 的 UAPI 用户态可见性问题（例如 __u128）必须补在这里才会生效。
if [ -d toolchain/kernel-headers/patches ]; then
	echo "----- toolchain/kernel-headers/patches 内容 -----"
	ls -1 toolchain/kernel-headers/patches || true
else
	echo "::warning::toolchain/kernel-headers/patches 不存在，7.3 UAPI 补丁不会被应用到工具链头文件！"
fi

# 4d) Linux 7.3 重构了 crypto/ 目录，一批模块改了名：
#       crypto/sha3_generic.ko     -> crypto/sha3.ko
#       crypto/blake2b_generic.ko  -> crypto/blake2b.ko
#       crypto/aes_generic.ko      -> crypto/aes.ko
#       （sm3_generic/sm3 连 Kconfig 符号都改了，那种情况 defconfig 会自动丢包，不用管）
#     OpenWrt 的 package/kernel/linux/modules/crypto.mk 里 FILES/AUTOLOAD 还是旧名字，
#     安装阶段会直接报 ERROR: module 'xxx' is missing. 让整个 package/kernel/linux 红掉。
#     只在 7.3 构建时改 —— 其它工作流还是 6.x，模块名不能动。
IS73=""
echo "${ALL_DEVICES:-}" | grep -q "7\.3" && IS73=1
if [ -z "$IS73" ] && [ -f target/linux/msm89xx/Makefile ] \
	&& grep -q "KERNEL_TESTING_PATCHVER:=7.3" target/linux/msm89xx/Makefile; then
	IS73=1
fi
CM=package/kernel/linux/modules/crypto.mk
if [ -n "$IS73" ]; then
	if [ -f "$CM" ]; then
		sed -i \
			-e 's#/crypto/sha3_generic\.ko#/crypto/sha3.ko#g' \
			-e 's#AutoProbe,sha3_generic#AutoProbe,sha3#g' \
			-e 's#/crypto/blake2b_generic\.ko#/crypto/blake2b.ko#g' \
			-e 's#AutoProbe,blake2b_generic#AutoProbe,blake2b#g' \
			-e 's#/crypto/aes_generic\.ko#/crypto/aes.ko#g' \
			-e 's#AutoProbe,aes_generic#AutoProbe,aes#g' \
			"$CM"
		echo "✅ 已按 Linux 7.3 的 crypto 模块改名修正 $CM："
		grep -nE "sha3|blake2b|aes_generic" "$CM" | head -20
	else
		echo "::warning::找不到 $CM —— 7.3 crypto 模块改名修正未执行"
	fi
else
	echo "ℹ️ 非 7.3 构建（ALL_DEVICES='${ALL_DEVICES:-}'），跳过 crypto 模块改名修正"
fi

# 5) 兜底：万一文件是 Windows 编辑器上传带上的 CRLF，make/patch 都会出问题，统一清掉行尾 \r
for f in target/linux/generic/kernel-7.3 \
	target/linux/generic/config-7.3 \
	target/linux/msm89xx/config-7.3 \
	target/linux/msm89xx/patches-7.3/*.patch; do
	if [ -f "$f" ]; then
		sed -i 's/\r$//' "$f"
	fi
done

# 5b) 7.3 删掉了 UAPI 头 include/uapi/linux/atmsvc.h（v6.18 还在，v7.3-rc5 上已 404）。
#     linux-atm 的 src/test/isp.c 和 ispl_y.y 都 #include <linux/atmsvc.h>，
#     而它是用 TARGET_CFLAGS += -I$(LINUX_DIR)/user_headers/include 编的
#     （目标内核导出的头文件，不是工具链头文件），于是 7.3 上直接
#     fatal error: linux/atmsvc.h: No such file。
#
#     两层修复（互为冗余，任一生效即可，确保稳健）：
#     [主] 在内核树里用平台补丁补回 include/uapi/linux/atmsvc.h —— 这是"正统"修法：
#          headers_install 会把 include/uapi/** 全部导出到 user_headers，
#          正是 linux-atm 找头文件的地方。补丁落在 target/linux/msm89xx/patches-7.3/，
#          若仓库漏提交，下面会就地生成（从刚写好的 compat 头派生）。
#     [备] 同时把同一份头放进 linux-atm 包内 compat/linux/ 并追加一条 -I，
#          即使平台补丁因故未生效，包也能自行找到头文件。
#     依赖的 atmapi.h / atm.h / atmioc.h 在 7.3 里都还在（atm_kptr_t、
#     __ATM_API_ALIGN、sockaddr_atmsvc、ATMIOC_SPECIAL 均健在），可原样复用。
ATM_DIR=package/network/utils/linux-atm
if [ -d "$ATM_DIR" ]; then
	mkdir -p "$ATM_DIR/compat/linux"
	cat > "$ATM_DIR/compat/linux/atmsvc.h" <<'ATMSVC_EOF'
/* SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note */
/* atmsvc.h - ATM signaling kernel-demon interface definitions */

/* Written 1995-2000 by Werner Almesberger, EPFL LRC/ICA */


#ifndef _LINUX_ATMSVC_H
#define _LINUX_ATMSVC_H

#include <linux/atmapi.h>
#include <linux/atm.h>
#include <linux/atmioc.h>


#define ATMSIGD_CTRL _IO('a',ATMIOC_SPECIAL)
				/* become ATM signaling demon control socket */

enum atmsvc_msg_type { as_catch_null, as_bind, as_connect, as_accept, as_reject,
		       as_listen, as_okay, as_error, as_indicate, as_close,
		       as_itf_notify, as_modify, as_identify, as_terminate,
		       as_addparty, as_dropparty };

struct atmsvc_msg {
	enum atmsvc_msg_type type;
	atm_kptr_t vcc;
	atm_kptr_t listen_vcc;		/* indicate */
	int reply;			/* for okay and close:		   */
					/*   < 0: error before active	   */
					/*        (sigd has discarded ctx) */
					/*   ==0: success		   */
				        /*   > 0: error when active (still */
					/*        need to close)	   */
	struct sockaddr_atmpvc pvc;	/* indicate, okay (connect) */
	struct sockaddr_atmsvc local;	/* local SVC address */
	struct atm_qos qos;		/* QOS parameters */
	struct atm_sap sap;		/* SAP */
	unsigned int session;		/* for p2pm */
	struct sockaddr_atmsvc svc;	/* SVC address */
} __ATM_API_ALIGN;

/*
 * Message contents: see ftp://icaftp.epfl.ch/pub/linux/atm/docs/isp-*.tar.gz
 */

/*
 * Some policy stuff for atmsigd and for net/atm/svc.c. Both have to agree on
 * what PCR is used to request bandwidth from the device driver. net/atm/svc.c
 * tries to do better than that, but only if there's no routing decision (i.e.
 * if signaling only uses one ATM interface).
 */

#define SELECT_TOP_PCR(tp) ((tp).pcr ? (tp).pcr : \
  (tp).max_pcr && (tp).max_pcr != ATM_MAX_PCR ? (tp).max_pcr : \
  (tp).min_pcr ? (tp).min_pcr : ATM_MAX_PCR)

#endif
ATMSVC_EOF
	sed -i 's/\r$//' "$ATM_DIR/compat/linux/atmsvc.h"

	# [主修复] 在内核树补回 include/uapi/linux/atmsvc.h（正交修法，优先于包内 compat）。
	#     headers_install 会把 include/uapi/** 全部导出到 user_headers，
	#     而 linux-atm 正是用 -I$(LINUX_DIR)/user_headers/include 找头文件，
	#     所以补回内核树后包自然能编过。补丁落在 target/linux/msm89xx/patches-7.3/，
	#     即使仓库漏提交该补丁，这里也从刚写好的 compat 头就地生成，保证 self-heal。
	PATCH_DIR=target/linux/msm89xx/patches-7.3
	PATCH_FILE="$PATCH_DIR/0100-restore-uapi-linux-atmsvc-header.patch"
	if [ -f "$PATCH_FILE" ]; then
		echo "✅ 内核补丁 $PATCH_FILE 已在仓库中，主修复就绪"
	else
		mkdir -p "$PATCH_DIR"
		{
			printf -- '--- /dev/null\t1970-01-01 08:00:00.000000000 +0800\n'
			printf -- '+++ b/include/uapi/linux/atmsvc.h\t2026-10-03 12:00:00.000000000 +0800\n'
			printf -- '@@ -0,0 +1,%d @@\n' "$(wc -l < "$ATM_DIR/compat/linux/atmsvc.h")"
			sed 's/^/+/' "$ATM_DIR/compat/linux/atmsvc.h"
		} > "$PATCH_FILE"
		sed -i 's/\r$//' "$PATCH_FILE"
		echo "✅ 内核补丁 $PATCH_FILE 已就地生成（仓库漏提交时自修复）"
	fi

	if [ -f "$ATM_DIR/Makefile" ]; then
		if ! grep -q "linux-atm/compat" "$ATM_DIR/Makefile"; then
			printf '\n# 7.3 移除了 include/uapi/linux/atmsvc.h，用包内 compat 目录补回（见 diy-part1.sh）\nTARGET_CFLAGS += -I$(TOPDIR)/%s/compat\n' "$ATM_DIR" >> "$ATM_DIR/Makefile"
			echo "✅ linux-atm 已追加 -I compat（补回 linux/atmsvc.h）"
		else
			echo "ℹ️ linux-atm 已带 compat -I，跳过"
		fi
		grep -n "TARGET_CFLAGS" "$ATM_DIR/Makefile" || true
	else
		echo "⚠️ 未找到 $ATM_DIR/Makefile，无法补 atmsvc.h 的 -I"
	fi
else
	echo "ℹ️ 上游没有 package/network/utils/linux-atm，跳过 ATM 头兼容"
fi

# 6) 最终校验：还缺就报错，避免后面以"编了个没补丁的内核"的方式假成功
miss=0
for f in target/linux/generic/kernel-7.3 \
	target/linux/generic/config-7.3 \
	target/linux/msm89xx/config-7.3 \
	target/linux/msm89xx/patches-7.3; do
	if [ -e "$f" ]; then
		echo "✅ $f"
	else
		echo "❌ 仍然缺少 $f —— 请确认仓库里 scripts/msm89xx/target/ 下的 7.3 新文件已提交并推送"
		miss=1
	fi
done
if [ "$miss" = "1" ]; then
	echo "::error::7.3-rc5 所需文件缺失，本次若使用 CONFIG_TESTING_KERNEL=y 会编译失败"
fi

# 注意：GitHub 的 shell 是 bash -e（-e 会把"返回非 0 的最后一条命令"当成步骤失败），
# 所以本文件里一律用 if...fi，不能写 `[ 条件 ] && 命令` —— 条件为假时返回 1 会让整个步骤红掉。
exit 0

