#!/bin/bash
#

# Modify default IP
sed -i 's/192.168.1.1/192.168.10.1/g' package/base-files/files/bin/config_generate

# eth0
sed -i "s/ucidef_set_interface_lan 'eth0'/ucidef_set_interface_lan 'br-lan'/" package/base-files/files/etc/board.d/99-default_network

# Modify default theme
sed -i 's/luci-theme-material/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# DbusSmsForwardCPlus
# 必须在 make defconfig 之前把源码放进 package/，否则
# CONFIG_PACKAGE_DbusSmsForwardCPlus=y 会被 defconfig 静默丢弃。
if [ ! -d package/DbusSmsForwardCPlus ]; then
	git clone --depth 1 https://github.com/lkiuyu/DbusSmsForwardCPlus package/DbusSmsForwardCPlus \
		|| echo "⚠️ DbusSmsForwardCPlus 克隆失败，本次编译将跳过该包"
else
	echo "✅ DbusSmsForwardCPlus 已存在"
fi

# luci-app-turboacc (mufeng05, 内核 6.18 已验证)
# 必须在 make defconfig 之前把源码放进 package/，否则 CONFIG_PACKAGE_luci-app-turboacc=y 会被静默丢弃。
# 只取 lede/luci-app-turboacc（纯 LuCI 应用 + 可选 kmod-tcp-bbr），不应用 SFE 内核补丁，
# 以免在 6.18 上编译失败，也避免绕过 CAKE。包默认 set '0'（关闭），不会自动开流控。
if [ ! -d package/luci-app-turboacc ]; then
	if git clone --depth 1 --branch main https://github.com/mufeng05/turboacc.git package/_turboacc_src; then
		cp -rf package/_turboacc_src/lede/luci-app-turboacc package/luci-app-turboacc
		rm -rf package/_turboacc_src
		echo "✅ luci-app-turboacc 已放入 package/"
	else
		echo "⚠️ luci-app-turboacc 克隆失败，本次编译将跳过该包"
	fi
else
	echo "✅ luci-app-turboacc 已存在"
fi

# 直接放在 package/ 下的 LuCI 应用，其 Makefile 用 include ../../luci.mk，
# 会从 package/luci.mk 解析；但上游树里没有该文件（luci.mk 实际在 feeds/luci/luci.mk）。
# 建一个符号链接，保证 luci-app-turboacc 能正常编译。feeds update 之后 feeds/luci/luci.mk 已存在。
if [ ! -e package/luci.mk ] && [ -e feeds/luci/luci.mk ]; then
	ln -s feeds/luci/luci.mk package/luci.mk
	echo "✅ 已建 package/luci.mk -> feeds/luci/luci.mk"
fi

# mosdns 打包冲突修复
# luci-app-mosdns 依赖 mosdns（+mosdns），二者必然同时被安装；但 luci-app-mosdns 的
# root/etc/init.d/mosdns 与 mosdns 核心包自带的同名 init 脚本冲突，opkg 安装阶段会报
# “trying to overwrite etc/init.d/mosdns owned by mosdns” 而构建失败。
# 去掉 luci-app-mosdns 自带的重复 init 脚本，保留 mosdns 核心包的（功能正常、UI 仍调用它）。
for p in \
	feeds/small/luci-app-mosdns/root/etc/init.d/mosdns \
	package/feeds/small/luci-app-mosdns/root/etc/init.d/mosdns; do
	if [ -f "$p" ]; then
		rm -f "$p"
		echo "✅ 已移除冲突文件 $p（避免与 mosdns 核心包冲突）"
	fi
done

# 北大源
cp -r "$GITHUB_WORKSPACE/scripts/files-8916" "$GITHUB_WORKSPACE/openwrt/files"
ls -R "$GITHUB_WORKSPACE/openwrt/files"

