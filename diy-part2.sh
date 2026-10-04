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

# mosdns 打包冲突修复（v2 —— 2026-10-04 修正）
# 旧实现只比对 feeds/small/mosdns/{root,files}，但 kenzok8/small 的 mosdns 目录
# **只有 Makefile + patches/**（没有 root/、没有 files/），而真正提供
# /etc/init.d/mosdns 的是 feeds/packages/net/mosdns —— 它是在 Makefile 里用
#     $(INSTALL_BIN) $(PKG_BUILD_DIR)/scripts/openwrt/mosdns-init-openwrt $(1)/etc/init.d/mosdns
# 装出来的。所以按"目录比对"永远匹配不到，旧逻辑一直静默空转（没有任何输出），
# 结果 r17 在 install 阶段报：
#     ERROR: luci-app-mosdns-1.7.14-r1: trying to overwrite etc/init.d/mosdns owned by mosdns-5.3.3-r1.
#
# 保留哪一个：luci-app-mosdns 自带的 /etc/init.d/mosdns 是**完整版**
# （procd + 读 uci mosdns.config.configfile + 用 /usr/share/mosdns/mosdns.uc，
#  被 LuCI 前端和 rpcd 后端依赖），核心包那个只是上游简单脚本（读 /etc/mosdns/config.yaml）。
# 若让核心版胜出，LuCI 里改的配置不会被 mosdns 加载 —— 属于功能回退。
# 因此：删掉**核心包 Makefile 里安装 /etc/init.d/mosdns 的那一行**，让 LuCI 版成为唯一提供者。
MOSDNS_MK=feeds/packages/net/mosdns/Makefile
if [ -f "$MOSDNS_MK" ]; then
	if grep -q 'INSTALL_BIN.*etc/init\.d/mosdns' "$MOSDNS_MK"; then
		sed -i '/INSTALL_BIN.*etc\/init\.d\/mosdns/d' "$MOSDNS_MK"
		echo "✅ 已移除核心 mosdns 包对 /etc/init.d/mosdns 的安装，改用 luci-app-mosdns 的完整版"
	else
		echo "ℹ️ 核心 mosdns 包未安装 /etc/init.d/mosdns，无需处理"
	fi
else
	echo "ℹ️ 未找到 $MOSDNS_MK，跳过 mosdns 冲突修复"
fi

# 兜底：万一还有别的重名文件，把 luci-app-mosdns/root 下与 mosdns 核心包
# 实际安装路径重名的文件也清掉（安装路径从核心包 Makefile 的 $(1)/... 解析得到，
# 这样即使核心包把文件写在 Makefile 里而不是 root/ 目录里，也能被发现）。
python3 - <<'PY_MOSDNS'
import io
import os
import re

cores = ["feeds/packages/net/mosdns", "feeds/small/mosdns"]
luci_root = "feeds/small/luci-app-mosdns/root"

paths = set()
for d in cores:
    mk = os.path.join(d, "Makefile")
    if os.path.isfile(mk):
        src = io.open(mk, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'\$\(1\)/([A-Za-z0-9_./@+-]+)', src):
            paths.add(m.group(1))
    for sub in ("root", "files"):
        base = os.path.join(d, sub)
        if os.path.isdir(base):
            for dp, _dn, fns in os.walk(base):
                for fn in fns:
                    paths.add(os.path.relpath(os.path.join(dp, fn), base))

removed = 0
if os.path.isdir(luci_root):
    for dp, _dn, fns in os.walk(luci_root):
        for fn in fns:
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, luci_root)
            if rel in paths:
                os.remove(full)
                print("  removed luci-app-mosdns/root/%s (core also provides it)" % rel)
                removed += 1
    print("mosdns 兜底清理：核心包提供 %d 个路径，移除重名文件 %d 个" % (len(paths), removed))
else:
    print("ℹ️ 未找到 %s，跳过兜底清理" % luci_root)
PY_MOSDNS

# 北大源
cp -r "$GITHUB_WORKSPACE/scripts/files-8916" "$GITHUB_WORKSPACE/openwrt/files"
ls -R "$GITHUB_WORKSPACE/openwrt/files"

