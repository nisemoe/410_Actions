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
# 1) generic 层 config-7.3：上游不会为新内核提供，用当前最新的 config-x.y 复制一份。
#    kconfig 里已不存在/改名的符号会在内核 olddefconfig 阶段自动丢弃或取默认值。
if [ ! -f target/linux/generic/config-7.3 ]; then
	base=$(ls -1 target/linux/generic/config-* 2>/dev/null | grep -E 'config-[0-9]+\.[0-9]+$' | sort -V | tail -1)
	if [ -n "$base" ]; then
		cp -f "$base" target/linux/generic/config-7.3
		echo "✅ 已由 $base 生成 target/linux/generic/config-7.3"
	else
		echo "⚠️ 未找到可用的 generic config-* 作为 config-7.3 模板"
	fi
else
	echo "✅ target/linux/generic/config-7.3 已存在（上游已提供）"
fi

# 2) 校验 7.3 编译必需的文件是否齐全
for f in target/linux/generic/kernel-7.3 \
	target/linux/generic/config-7.3 \
	target/linux/msm89xx/config-7.3 \
	target/linux/msm89xx/patches-7.3; do
	if [ -e "$f" ]; then
		echo "✅ $f"
	else
		echo "⚠️ 缺少 $f —— 使用 7.3-rc5 内核编译会失败"
	fi
done

