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
		printf 'LINUX_VERSION-7.3 = -rc5\n' > target/linux/generic/kernel-7.3
		echo "⚠️ 仓库未带 generic/kernel-7.3，已按 -rc5 现场生成"
	fi
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

# 5) 兜底：万一文件是 Windows 编辑器上传带上的 CRLF，make/patch 都会出问题，统一清掉行尾 \r
for f in target/linux/generic/kernel-7.3 \
	target/linux/generic/config-7.3 \
	target/linux/msm89xx/config-7.3 \
	target/linux/msm89xx/patches-7.3/*.patch; do
	if [ -f "$f" ]; then
		sed -i 's/\r$//' "$f"
	fi
done

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

