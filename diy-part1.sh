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

# 4e) Linux 7.3 又把 raid6 / xor 搬了家（lib/raid6 -> lib/raid/raid6，crypto/xor.o -> lib/raid/xor/xor.o）：
#       lib/raid6/raid6_pq.ko       -> lib/raid/raid6/raid6_pq.ko
#       crypto/xor.ko               -> lib/raid/xor/xor.ko
#       arch/<arch>/lib/xor-neon.ko -> 7.3 起并进 xor.ko，不再是独立模块
#                                      （lib.mk 里那个 wildcard 判断会自动走 else 分支，无需改）
#     v7.3-rc5 证据：
#       lib/Makefile            : obj-y += math/ crc/ crypto/ tests/ vdso/ raid/
#       lib/raid/Makefile       : obj-y += xor/ raid6/
#       lib/raid/raid6/Makefile : obj-$(CONFIG_RAID6_PQ)   += raid6_pq.o
#       lib/raid/xor/Makefile   : obj-$(CONFIG_XOR_BLOCKS) += xor.o
#     关键：CONFIG_RAID6_PQ / CONFIG_XOR_BLOCKS 在 7.3 里**依然存在**（lib/raid/Kconfig，tristate），
#     而 config-7.3 是从 config-6.18 复制来的、这两个都是 =m。于是 include/kernel.mk 的可用性判断
#         ifneq ($(if <plain KCONFIG syms>, $(filter m y, ...), .),)
#     得到 B="m" -> 判定 kmod "可用" -> 走安装分支，按旧路径找不到 .ko：
#         ERROR: module '/.../linux-7.3-rc5/lib/raid6/raid6_pq.ko' is missing.
#     于是整个 package/kernel/linux 编译失败。又因为 include/verbose.mk 在非 V=s 时把子 make 的
#     stdout+stderr 全部丢进 /dev/null，日志里只剩一行 "ERROR: package/kernel/linux failed to build."。
#     只在 7.3 构建时改 —— 其它工作流还是 6.x，6.x 的路径是 lib/raid6、crypto/xor.ko，不能动。
LM=package/kernel/linux/modules/lib.mk
if [ -n "$IS73" ]; then
	if [ -f "$LM" ]; then
		sed -i \
			-e 's#lib/raid6/raid6_pq\.ko#lib/raid/raid6/raid6_pq.ko#g' \
			-e 's#crypto/xor\.ko#lib/raid/xor/xor.ko#g' \
			"$LM"
		echo "✅ 已按 Linux 7.3 的 raid6/xor 新路径修正 $LM："
		grep -nE "raid6_pq\.ko|xor\.ko|xor-neon\.ko" "$LM" | head -20
	else
		echo "::warning::找不到 $LM —— 7.3 raid6/xor 路径修正未执行"
	fi
else
	echo "ℹ️ 非 7.3 构建（ALL_DEVICES='${ALL_DEVICES:-}'），跳过 raid6/xor 路径修正"
fi

# 4f) Linux 7.3 把 lib/crypto 拆成了一大批独立模块，并且把 crypto/*.c 改成薄壳：
#       crypto/Kconfig:  CRYPTO_BLAKE2B select CRYPTO_LIB_BLAKE2B
#                        CRYPTO_SHA3    select CRYPTO_LIB_SHA3
#                        CRYPTO_SHA1    select CRYPTO_LIB_SHA1
#                        CRYPTO_GCM     select CRYPTO_LIB_GF128HASH
#                        CRYPTO_DRBG    select CRYPTO_LIB_SHA512
#                        CRYPTO_JITTERENTROPY select CRYPTO_LIB_SHA3
#       lib/crypto/Makefile: obj-$(CONFIG_CRYPTO_LIB_BLAKE2B) += libblake2b.o
#                            obj-$(CONFIG_CRYPTO_LIB_SHA3)    += libsha3.o   ... 等等
#     于是 crypto/*.ko 里出现对 lib/crypto/lib*.ko 的**未解析符号**。OpenWrt 的
#     include/package-ipkg.mk 依赖检查只看“同一个 ipkg 里装了哪些 .ko”，
#     round-12 实测直接红掉（topdir 复现日志 repro_package_kernel_linux.log）：
#         Package kmod-crypto-blake2b is missing dependencies for the following libraries:
#         libblake2b.ko
#         make[2]: *** [modules/crypto.mk:90: .../kmod-crypto-blake2b-7.3_rc5-r1.apk] Error 1
#     修法：把对应的 lib/crypto/lib*.ko 一起装进同一个包。
#     关键：用 $(if $(filter m,$(CONFIG_CRYPTO_LIB_*)),...) 包住。
#     include/kernel.mk 里有
#         ifeq ($(DUMP)$(TARGET_BUILD),)
#           -include $(LINUX_DIR)/.config
#         endif
#     内核配置符号在 kmod 包里就是普通 make 变量（KernelPackage 的可用性判断就是靠这个），
#     所以：lib 真的以 =m 构建 -> 加进去（否则会缺依赖）；=y 编进 vmlinux -> 自动跳过
#     （否则会 "ERROR: module '...' is missing."）。两种情形都安全。
#     顺带：4d 只改了 FILES 和 AutoProbe，AUTOLOAD 里残留的旧模块名也要一起改，
#     否则 /etc/modules.d/09-crypto-blake2b 里会写 blake2b_generic，开机 modprobe 失败。
#     只在 7.3 构建时改 —— 其它工作流还是 6.x，不能动。
if [ -n "$IS73" ]; then
	if [ -f "$CM" ]; then
		python3 - "$CM" <<'PY_CRYPTO73'
import re
import sys

path = sys.argv[1]
src = open(path, encoding='utf-8', errors='surrogateescape').read()
original = src

failures = []


def guard(sym, rel):
    return '$(if $(filter m,$(CONFIG_%s)),$(LINUX_DIR)/%s)' % (sym, rel)


def sub(label, pattern, repl):
    global src
    src, n = re.subn(pattern, lambda m, r=repl: r, src, count=1)
    if not n:
        failures.append(label)


def wrap(label, literal, sym, rel):
    global src
    if literal not in src:
        failures.append(label)
        return
    src = src.replace(literal, guard(sym, rel), 1)


# --- packages that must now also ship a lib/crypto helper module -------------
sub('crypto-blake2b FILES',
    r'(?m)^  FILES:=\$\(LINUX_DIR\)/crypto/blake2b(?:_generic)?\.ko\n',
    '  FILES:= \\\n'
    '\t$(LINUX_DIR)/crypto/blake2b.ko \\\n'
    '\t%s\n' % guard('CRYPTO_LIB_BLAKE2B', 'lib/crypto/libblake2b.ko'))

sub('crypto-blake2b AUTOLOAD',
    r'(?m)^  AUTOLOAD:=\$\(call AutoLoad,09,blake2b(?:_generic)?\)\n',
    '  AUTOLOAD:=$(call AutoLoad,09,blake2b)\n')

sub('crypto-sha3 FILES',
    r'(?m)^  FILES:=\$\(LINUX_DIR\)/crypto/sha3(?:_generic)?\.ko\n',
    '  FILES:= \\\n'
    '\t$(LINUX_DIR)/crypto/sha3.ko \\\n'
    '\t%s\n' % guard('CRYPTO_LIB_SHA3', 'lib/crypto/libsha3.ko'))

sub('crypto-sha3 AUTOLOAD',
    r'(?m)^  AUTOLOAD:=\$\(call AutoLoad,09,sha3(?:_generic)?\)\n',
    '  AUTOLOAD:=$(call AutoLoad,09,sha3)\n')

sub('crypto-sha1 FILES',
    r'(?m)^  FILES:=\$\(LINUX_DIR\)/crypto/sha1(?:_generic)?\.ko(?:@[\w.]+)? \\\n'
    r'\t\$\(LINUX_DIR\)/crypto/sha1\.ko(?:@[\w.]+)?\n',
    '  FILES:= \\\n'
    '\t$(LINUX_DIR)/crypto/sha1_generic.ko@lt6.18 \\\n'
    '\t$(LINUX_DIR)/crypto/sha1.ko@ge6.18 \\\n'
    '\t%s\n' % guard('CRYPTO_LIB_SHA1', 'lib/crypto/libsha1.ko'))

sub('crypto-gcm FILES',
    r'(?m)^  FILES:=\$\(LINUX_DIR\)/crypto/gcm\.ko\n',
    '  FILES:= \\\n'
    '\t$(LINUX_DIR)/crypto/gcm.ko \\\n'
    '\t%s\n' % guard('CRYPTO_LIB_GF128HASH', 'lib/crypto/libgf128hash.ko'))

# --- pre-existing unconditional lib/crypto entries: guard them as well -------
wrap('crypto-arc4 libarc4.ko',
     '$(LINUX_DIR)/lib/crypto/libarc4.ko',
     'CRYPTO_LIB_ARC4', 'lib/crypto/libarc4.ko')

wrap('crypto-des libdes.ko',
     '$(LINUX_DIR)/lib/crypto/libdes.ko',
     'CRYPTO_LIB_DES', 'lib/crypto/libdes.ko')

wrap('crypto-gf128 gf128mul.ko',
     '$(LINUX_DIR)/lib/crypto/gf128mul.ko',
     'CRYPTO_LIB_GF128MUL', 'lib/crypto/gf128mul.ko')

wrap('crypto-md5 libmd5.ko',
     '$(LINUX_DIR)/lib/crypto/libmd5.ko@ge6.18',
     'CRYPTO_LIB_MD5', 'lib/crypto/libmd5.ko')

wrap('crypto-sha512 libsha512.ko',
     '$(LINUX_DIR)/lib/crypto/libsha512.ko@ge6.18',
     'CRYPTO_LIB_SHA512', 'lib/crypto/libsha512.ko')

# --- 4g) Linux 7.3 删掉了 crypto/ghash-generic.c ---------------------------------
#     GHASH / POLYVAL 搬进了 lib/crypto/libgf128hash.ko（已经由上面的
#     kmod-crypto-gcm 一起装走）。麻烦在于 crypto-ghash 的 KCONFIG 是
#         CONFIG_CRYPTO_GHASH          <- 7.3 里彻底不存在
#         CONFIG_CRYPTO_GHASH_ARM_CE   <- 7.3 里还在（arch/arm/crypto/Kconfig）
#     scripts/package-metadata.pl 的 gen_kconfig_overrides() 里：
#         if ($config{"CONFIG_PACKAGE_$package"} and ($config ne 'n')) {
#                 $kconfig{$config} = 'm';
#         }
#     只要 CONFIG_PACKAGE_kmod-crypto-ghash=y（本仓库 config/wf2-73.config 里就是 y），
#     它就会往 .config.override 里塞 CONFIG_CRYPTO_GHASH=m / CONFIG_CRYPTO_GHASH_ARM_CE=m，
#     include/kernel.mk 的可用性判断
#         ifneq ($(if <plain syms>,$(filter m y,$($(sym))),.),)
#     看到 =m 就判定"可用"，于是照样跑 install recipe，按 FILES 找 .ko：
#         ERROR: module '.../crypto/ghash-generic.ko' is missing.
#     所以必须把这个包的 FILES/AUTOLOAD 显式清空 —— 7.3 里它本来就不该产出任何模块。
sub('crypto-ghash FILES (crypto/ghash-generic.c removed in 7.3)',
    r'(?m)^  FILES:=\$\(LINUX_DIR\)/crypto/ghash-generic\.ko\n',
    '  # 7.3: crypto/ghash-generic.c 已删除（GHASH 由 lib/crypto/libgf128hash.ko\n'
    '  # 提供，随 kmod-crypto-gcm 一起安装）。这里必须留空，否则 install recipe\n'
    '  # 会因为找不到该 .ko 而 "ERROR: module ... is missing."\n'
    '  FILES:=\n')

sub('crypto-ghash AUTOLOAD',
    r'(?m)^  AUTOLOAD:=\$\(call AutoLoad,09,ghash-generic\)\n',
    '  AUTOLOAD:=\n')


if failures:
    sys.stderr.write('::error::7.3 crypto.mk patch did not match: %s\n' % ', '.join(failures))
    sys.exit(1)

if src == original:
    sys.stderr.write('::error::7.3 crypto.mk patch produced no change\n')
    sys.exit(1)

open(path, 'w', encoding='utf-8', errors='surrogateescape').write(src)
print('OK: patched %s' % path)
PY_CRYPTO73
		echo "✅ 已按 Linux 7.3 的 lib/crypto 拆分补全 $CM："
		grep -nE "lib/crypto/lib(blake2b|sha3|sha1|gf128hash|arc4|des|md5|sha512)|lib/crypto/gf128mul|AutoLoad,09,(blake2b|sha3)\)" "$CM" | head -40 || true
	else
		echo "::warning::找不到 $CM —— 7.3 lib/crypto 依赖修正未执行"
	fi
else
	echo "ℹ️ 非 7.3 构建（ALL_DEVICES='${ALL_DEVICES:-}'），跳过 lib/crypto 依赖修正"
fi

# 4h) Linux 7.3 的 lib/crypto 拆分还会波及**非 crypto.mk 的消费者**：
#     drivers/net/ppp/ppp_mppe.c 用 arc4_setkey/arc4_crypt，7.3 里这些符号由
#     lib/crypto/libarc4.ko 导出。round-13 实测内核 .config 确认：
#         CONFIG_CRYPTO_ARC4=m -> CONFIG_CRYPTO_LIB_ARC4=m   (其它 CRYPTO_LIB_* 都是 =y)
#     而 kmod-mppe 的 DEPENDS 只有 kmod-ppp +kmod-crypto-sha1，没人把 libarc4.ko
#     装进同一个 ipkg，于是 package-pack.mk 的 CheckDependencies 报：
#         Package kmod-mppe is missing dependencies for the following libraries:
#         libarc4.ko
#         make[2]: *** [modules/netsupport.mk:707: .../kmod-mppe-7.3_rc5-r1.apk] Error 1
#     双保险（任一生效即可）：
#       [1] DEPENDS 加 +kmod-crypto-arc4 —— kmod-crypto-arc4 的 .provides 里有 libarc4.ko，
#           package-pack.mk 会把 IDEPEND 的 provides 并进来，依赖即满足。
#       [2] FILES 里再挂一份带守卫的 lib/crypto/libarc4.ko —— 万一
#           kmod-crypto-arc4 变成空包（unavailable），自己装也照样能过。
#           守卫保证：=m 才加（文件存在），=y 编进 vmlinux 则不加
#           （否则 "ERROR: module ... is missing."）。
#     rootfs 安装是纯 CP（不做依赖解析/冲突检测），同一份 .ko
#     被两个包装进 /lib/modules/<ver>/ 不会报错。
if [ -n "$IS73" ]; then
	NM=package/kernel/linux/modules/netsupport.mk
	if [ -f "$NM" ]; then
		python3 - "$NM" <<'PY_MPPE73'
import io
import re
import sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8', errors='surrogateescape', newline='\n').read()
original = src
failures = []

LIBARC4 = '$(if $(filter m,$(CONFIG_CRYPTO_LIB_ARC4)),$(LINUX_DIR)/lib/crypto/libarc4.ko)'

m = re.search(r'(?ms)^define KernelPackage/mppe\n.*?^endef$', src)
if not m:
    failures.append('KernelPackage/mppe block not found')
    blk = None
else:
    blk = m.group(0)
    new = blk

    # [1] DEPENDS: make sure +kmod-crypto-arc4 is there
    if '+kmod-crypto-arc4' not in new:
        def _dep(mo):
            line = mo.group(0)
            if '+kmod-crypto-arc4' in line:
                return line
            if line.endswith(' '):
                return line + '+kmod-crypto-arc4'
            return line + ' +kmod-crypto-arc4'

        new, n = re.subn(r'(?m)^  DEPENDS:=.*$', _dep, new, count=1)
        if not n:
            # no DEPENDS line at all -> insert one right after the TITLE line
            new, n = re.subn(r'(?m)^  TITLE:=.*$', lambda mo: mo.group(0)
                             + '\n  DEPENDS:=+kmod-crypto-arc4', new, count=1)
            if not n:
                failures.append('mppe DEPENDS')

    # [2] FILES: append the guarded libarc4.ko
    if LIBARC4 not in new:
        def _files(mo):
            line = mo.group(0)
            if LIBARC4 in line:
                return line
            return line + ' ' + LIBARC4

        new, n = re.subn(r'(?m)^  FILES:=.*$', _files, new, count=1)
        if not n:
            new, n = re.subn(r'(?m)^  TITLE:=.*$', lambda mo: mo.group(0)
                             + '\n  FILES:=' + LIBARC4, new, count=1)
            if not n:
                failures.append('mppe FILES')

    src = src[:m.start()] + new + src[m.end():]

if failures:
    sys.stderr.write('::error::7.3 netsupport.mk mppe patch did not match: %s\n'
                     % ', '.join(failures))
    sys.exit(1)

if src == original:
    sys.stderr.write('::error::7.3 netsupport.mk mppe patch produced no change\n')
    sys.exit(1)

io.open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='\n').write(src)
print('OK: patched %s' % path)
PY_MPPE73
		echo "✅ 已按 Linux 7.3 修复 kmod-mppe 对 libarc4.ko 的依赖："
		grep -nE "kmod-crypto-arc4|ppp_mppe\.ko|lib/crypto/libarc4" "$NM" | head -20 || true
	else
		echo "::warning::找不到 $NM —— 7.3 kmod-mppe/libarc4 依赖修正未执行"
	fi
else
	echo "ℹ️ 非 7.3 构建（ALL_DEVICES='${ALL_DEVICES:-}'），跳过 kmod-mppe/libarc4 修正"
fi

# 4i) Linux 7.3 与 backports-7.2（mac80211 包）的冲突：
#     struct net_device 的 ieee80211_ptr 成员在 7.3 里被
#         #if IS_ENABLED(CONFIG_CFG80211)
#     包着（include/linux/netdevice.h:2377）。而 OpenWrt 的 kmod-cfg80211
#     是**不带 KCONFIG 的** KernelPackage（FILES 全部来自 $(PKG_BUILD_DIR)，
#     即 backports 自己的产物），所以内核 .config 里根本没有
#     CONFIG_CFG80211 -> 该成员不存在。backports-7.2 的
#     include/net/cfg80211.h 里有
#         cfg80211_unregister_netdevice() { cfg80211_unregister_wdev(dev->ieee80211_ptr); }
#     于是 wcn36xx/main.c 直接编译失败：
#         include/net/cfg80211.h:10122:37: error: 'struct net_device' has no member named 'ieee80211_ptr'
#     修法（最直接、零副作用）：用平台补丁把这个 #if 去掉，
#     让 ieee80211_ptr 无条件存在。struct wireless_dev 在 netdevice.h:71
#     已有无条件前向声明，去掉 #if 即可编译；只多 8 字节/netdev，
#     对内核其它代码是纯加成员，无影响。
if [ -n "$IS73" ]; then
	PD=target/linux/msm89xx/patches-7.3
	mkdir -p "$PD"
	cat > "$PD/994-netdevice-ieee80211-ptr-unconditional.patch" <<'NETDEV73_EOF'
--- a/include/linux/netdevice.h
+++ b/include/linux/netdevice.h
@@ -2374,9 +2374,7 @@
 #if IS_ENABLED(CONFIG_TIPC)
 	struct tipc_bearer __rcu *tipc_ptr;
 #endif
-#if IS_ENABLED(CONFIG_CFG80211)
 	struct wireless_dev	*ieee80211_ptr;
-#endif
 #if IS_ENABLED(CONFIG_IEEE802154) || IS_ENABLED(CONFIG_6LOWPAN)
 	struct wpan_dev		*ieee802154_ptr;
 #endif
NETDEV73_EOF
	cat > "$PD/993-string-strncpy-shim.patch" <<'STRING73_EOF'
--- a/include/linux/string.h
+++ b/include/linux/string.h
@@ -256,6 +256,27 @@
 #ifndef __HAVE_ARCH_MEMCPY
 extern void * memcpy(void *,const void *,__kernel_size_t);
 #endif
+
+/*
+ * Linux 7.3 removed strncpy() from lib/string.c (and with it the declaration
+ * that used to live here).  Out-of-tree modules which still call it fail with
+ * "implicit declaration of function 'strncpy'".  Provide a behaviour-identical
+ * inline replacement (byte-for-byte the pre-7.3 kernel implementation) so such
+ * modules keep building.  'static inline' => no unused-function warning.
+ */
+static inline char *strncpy(char *dest, const char *src, __kernel_size_t count)
+{
+	char *tmp = dest;
+
+	while (count) {
+		if ((*tmp = *src) != 0)
+			src++;
+		tmp++;
+		count--;
+	}
+	return dest;
+}
+
 #ifndef __HAVE_ARCH_MEMMOVE
 extern void * memmove(void *,const void *,__kernel_size_t);
 #endif
STRING73_EOF
	echo "✅ 已写入 7.3 兼容补丁（$PD）："
	ls -1 "$PD" || true
else
	echo "ℹ️ 非 7.3 构建（ALL_DEVICES='${ALL_DEVICES:-}'），跳过 7.3 兼容补丁"
fi

# 4j) apk 版本号：7.3-rc5 会让**自带 PKG_VERSION 的 kmod 包**的版本号变成
#     7.3_rc5.2023.05.17~07d93b62-r3，apk-tools 直接拒绝：
#       ERROR: info field 'version' has invalid value: package version is invalid
#       make[2]: *** [Makefile:80: .../kmod-nft-fullcone-7.3_rc5.2023.05.17~07d93b62-r3.apk] Error 99
#     原因：apk 的版本语法是
#       <number>{.<number>}...[_suf<number>]...[~suf]...[-r<number>]
#     `_rc5` 之后不能再跟 `.number`。实测：
#       7.3_rc5-r1                      -> 合法（round-13 已构建）
#       7.3_rc5~<vermagic>-r1           -> 合法（EXTRA_DEPENDS 里的 kernel 约束）
#       7.3_rc5.2023.05.17~07d93b62-r3  -> 非法 ← 本轮报错点
#     修法：包自带 PKG_VERSION 时，内核部分只取主版本（7.3），
#     与 6.x 时代的 6.18.2023.05.17~07d93b62-r3 形状完全一致。
#     不带 PKG_VERSION 的包（kmod-crypto-* 等）保持 7.3_rc5-r1 不变。
#     EXTRA_DEPENDS 里的 kernel (=7.3_rc5~<vermagic>-rN) 不受影响，ABI 约束照旧。
#     非 rc 内核（6.18 等）：$(firstword $(subst -, ,6.18)) = 6.18，与原来等价。
if [ -n "$IS73" ]; then
	KMK=include/kernel.mk
	if [ -f "$KMK" ]; then
		python3 - "$KMK" <<'PY_VER73'
import io
import sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8', errors='surrogateescape', newline='\n').read()

OLD = ('    VERSION:=$(subst -rc,_rc,$(LINUX_VERSION))'
       '$(if $(PKG_VERSION),.$(PKG_VERSION))'
       '-r$(if $(PKG_RELEASE),$(PKG_RELEASE),$(LINUX_RELEASE))')
NEW = ('    VERSION:=$(if $(PKG_VERSION),$(firstword $(subst -, ,$(LINUX_VERSION))),'
       '$(subst -rc,_rc,$(LINUX_VERSION)))'
       '$(if $(PKG_VERSION),.$(PKG_VERSION))'
       '-r$(if $(PKG_RELEASE),$(PKG_RELEASE),$(LINUX_RELEASE))')

n = src.count(OLD)
if n != 1:
    sys.stderr.write('::error::kernel.mk VERSION line match count = %d\n' % n)
    sys.exit(1)

src = src.replace(OLD, NEW)
io.open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='\n').write(src)
print('OK: patched %s' % path)
PY_VER73
		echo "✅ 已修正 7.3-rc5 的 apk 版本号："
		grep -n "^    VERSION:=" "$KMK" || true
	else
		echo "::warning::找不到 $KMK —— apk 版本号修正未执行"
	fi
else
	echo "ℹ️ 非 7.3 构建（ALL_DEVICES='${ALL_DEVICES:-}'），跳过 apk 版本号修正"
fi

# 4k) Linux 7.3 又动了两个"老接口"，这正是 r15 剩下两个失败的根因：
#     (1) include/linux/kernel.h 不再 include <linux/hex.h>（6.18 里是有的，
#         就在 bitops.h 和 kstrtox.h 之间）。mac_pton() 的声明在
#         include/linux/hex.h —— 7.3 并没有删掉它（6.18/7.3 的 hex.h 逐字节相同），
#         只是不再被 kernel.h 顺带带出来。于是 backports-7.2 的
#             net/wireless/sysfs.c:42:14: error: implicit declaration of function 'mac_pton'
#         （package/kernel/mac80211 整棵树只报了这一条 error）
#         修法：把 #include <linux/hex.h> 加回 kernel.h，恢复 6.18 的可见性。
#     (2) open-app-filter（oaf 内核模块）的 oaf/src/af_client.c 只 include 了
#         <linux/netfilter.h> 和 <linux/netfilter_ipv6.h>，没有 include
#         <linux/netfilter_ipv4.h>，却用了 NF_IP_PRI_FIRST / NF_IP_PRI_LAST：
#             af_client.c:541:29: error: 'NF_IP_PRI_FIRST' undeclared here
#                                       (did you mean 'NF_IP6_PRI_FIRST'?)
#         这两个枚举值在 7.3 里仍在（只是 6.18 用 INT_MIN/INT_MAX，
#         7.3 改成 __KERNEL_INT_MIN/__KERNEL_INT_MAX，值不变）。
#         注意：不能用 #define 兜底 —— 枚举常量对预处理器不可见，
#         #ifndef 一定成立，宏会把头里的枚举名替换掉从而语法错。
#         修法：让 netfilter_ipv6.h 顺带把 netfilter_ipv4.h 带进来。
#         这两个头本就是孪生关系（ipv6 头的注释原文：
#         "this header was blatantly ripped from netfilter_ipv4.h"），
#         且 netfilter_ipv4.h 只 include netfilter.h + typelimits.h，
#         不存在循环包含问题。
if [ -n "$IS73" ]; then
	PD=target/linux/msm89xx/patches-7.3
	mkdir -p "$PD"
	cat > "$PD/995-kernel-h-hex-include.patch" <<'HEX73_EOF'
--- a/include/linux/kernel.h
+++ b/include/linux/kernel.h
@@ -21,6 +21,7 @@
 #include <linux/compiler.h>
 #include <linux/container_of.h>
 #include <linux/bitops.h>
+#include <linux/hex.h>
 #include <linux/kstrtox.h>
 #include <linux/log2.h>
 #include <linux/math.h>
HEX73_EOF
	cat > "$PD/996-netfilter-ipv6-include-ipv4.patch" <<'NFIPV4_73_EOF'
--- a/include/uapi/linux/netfilter_ipv6.h
+++ b/include/uapi/linux/netfilter_ipv6.h
@@ -12,5 +12,6 @@
 #include <linux/netfilter.h>
 #include <linux/typelimits.h>
+#include <linux/netfilter_ipv4.h>
 
 /* only for userspace compatibility */
 #ifndef __KERNEL__
NFIPV4_73_EOF
	echo "[ok] 4k) added 995-kernel-h-hex-include.patch / 996-netfilter-ipv6-include-ipv4.patch into $PD"
fi

# 4l) 和 4h) 同一类问题：Linux 7.3 把 lib/crypto 拆成独立模块后，
#     backports 的 mac80211.ko 链接到了 arc4 符号（WEP/TKIP），
#     打包时依赖检查直接拒绝：
#       Package kmod-mac80211 is missing dependencies for the following libraries:
#       libarc4.ko
#       make[2]: *** [Makefile:410: .../kmod-mac80211-7.3.7.2-r4.apk] Error 1
#     （注意：此时 backports 整棵树**已经编译成功**了 —— wcn36xx/ath/rtw88 全家的 .ko
#       都产出了，只剩这一个包在 apk 打包阶段被依赖检查拦下，不是编译错误。）
#
#     ★ 为什么用 +kmod-crypto-arc4 而不是只靠 FILES 里的 $(if ...)：
#       include/kernel.mk 第 192-194 行是
#           ifeq ($(DUMP)$(TARGET_BUILD),)
#             -include $(LINUX_DIR)/.config
#           endif
#       而元数据扫描（include/scan.mk）是带 DUMP=1 跑的，**扫描期根本不会 include
#       内核 .config**，所以扫描期 $(CONFIG_CRYPTO_LIB_ARC4) 是空的，
#       $(if $(filter m,...)) 一律为假 —— 只有 FILES 守卫是不够的。
#       4h) 里 kmod-mppe 能修好，靠的正是同时加的 `+kmod-crypto-arc4`
#       （DEPENDS -> IDEPEND -> kmod-crypto-arc4.provides 里含 libarc4.ko）。
#       这里对 kmod-mac80211 采用**完全相同的一对改动**。
#
#     已从 r16 的 step log 里取到权威内核配置，两个符号都确实为 m：
#       CONFIG_CRYPTO_LIB_ARC4=m
#       CONFIG_CRYPTO_ARC4=m        <- 所以 kmod-crypto-arc4 是真实非空包
#     FILES 里的守卫保留作第二层保险（构建期 DUMP 为空时它会生效）。
if [ -n "$IS73" ]; then
	MKM=package/kernel/mac80211/Makefile
	if [ -f "$MKM" ]; then
		python3 - "$MKM" <<'PY_MAC73'
import io
import re
import sys

path = sys.argv[1]
src = io.open(path, encoding='utf-8', errors='surrogateescape', newline='\n').read()

# locate the *exact* "define KernelPackage/mac80211" block (not /Default, /config, ...)
m = re.search(r'(?m)^define KernelPackage/mac80211\n(.*?)^endef\n', src, re.S)
if not m:
    sys.stderr.write('::error::mac80211: KernelPackage/mac80211 block not found\n')
    sys.exit(1)

blk = m.group(1)
orig = blk

GUARD = ' $(if $(filter m,$(CONFIG_CRYPTO_LIB_ARC4)),$(LINUX_DIR)/lib/crypto/libarc4.ko)'

# --- 1) DEPENDS += +kmod-crypto-arc4   (this is the part that actually fixes the check)
if '+kmod-crypto-arc4' not in blk:
    dm = re.search(r'(?m)^([ \t]*DEPENDS\+=.*)$', blk)
    if not dm:
        sys.stderr.write('::error::mac80211: DEPENDS+= line not found in KernelPackage/mac80211\n')
        sys.exit(1)
    old_dep = dm.group(1)
    new_dep = old_dep.rstrip() + ' +kmod-crypto-arc4'
    blk = blk.replace(old_dep, new_dep, 1)
    print('  DEPENDS: ' + old_dep)
    print('        -> ' + new_dep)
else:
    print('  DEPENDS: +kmod-crypto-arc4 already present, skipped')

# --- 2) FILES += guarded libarc4.ko   (second line of defence)
if 'libarc4.ko' not in blk:
    fm = re.search(r'(?m)^([ \t]*FILES:=[ \t]*\$\(PKG_BUILD_DIR\)/net/mac80211/mac80211\.ko[ \t]*)$', blk)
    if not fm:
        sys.stderr.write('::error::mac80211: FILES:= $(PKG_BUILD_DIR)/net/mac80211/mac80211.ko not found\n')
        sys.exit(1)
    old_files = fm.group(1)
    new_files = old_files.rstrip() + GUARD
    blk = blk.replace(old_files, new_files, 1)
    print('  FILES:   ' + old_files)
    print('        -> ' + new_files)
else:
    print('  FILES: libarc4.ko already present, skipped')

if blk == orig:
    sys.stderr.write('::error::mac80211: nothing changed\n')
    sys.exit(1)

src = src[:m.start(1)] + blk + src[m.end(1):]
io.open(path, 'w', encoding='utf-8', errors='surrogateescape', newline='\n').write(src)
print('OK: patched %s' % path)
PY_MAC73
		echo "[ok] 已给 kmod-mac80211 补上 libarc4.ko 依赖（+kmod-crypto-arc4 + FILES 守卫）"
	else
		echo "::warning::package/kernel/mac80211/Makefile 不存在，4l) 跳过"
	fi
fi

# 4m) libarc4.ko 的"双重归属" —— 安装期 apk 冲突：
#       ERROR: kmod-mac80211-7.3.7.2-r5: trying to overwrite
#              lib/modules/7.3-rc5/libarc4.ko owned by kmod-mppe-7.3_rc5-r1.
#     r17 已经把**所有包都编译出来了**（build_failed_pkgs.txt 为空），
#     这是 package/install 阶段才暴露的问题：kmod-mppe（4h）和
#     kmod-mac80211（4l）都通过
#         $(if $(filter m,$(CONFIG_CRYPTO_LIB_ARC4)),$(LINUX_DIR)/lib/crypto/libarc4.ko)
#     把同一个 lib/crypto/libarc4.ko 塞进了各自的 FILES，而 apk 不允许两个包拥有同一文件。
#
#     正确架构：libarc4.ko 应由**库的归属包** kmod-crypto-arc4 唯一提供，
#     其它包只声明依赖（+kmod-crypto-arc4），靠 IDEPEND -> provides 通过依赖检查。
#     因此这里做三件事：
#       1) crypto.mk 里 kmod-crypto-arc4 的 libarc4.ko 条目**去掉守卫**（无条件提供）；
#       2) netsupport.mk 里 kmod-mppe 的 FILES 去掉 libarc4.ko；
#       3) mac80211/Makefile 里 kmod-mac80211 的 FILES 同样去掉。
#     （2)(3) 的 DEPENDS 里已经有 +kmod-crypto-arc4，所以依赖检查照旧通过。
#     这样无论扫描期 $(CONFIG_CRYPTO_LIB_ARC4) 是否可见，都只有一个包拥有该文件；
#     而 kmod-crypto-arc4 的 provides 里一定含 libarc4.ko（字符串写死，不受守卫影响）。
if [ -n "$IS73" ]; then
	python3 - <<'PY_ARC4_OWNER'
import io
import os

GUARD = '$(if $(filter m,$(CONFIG_CRYPTO_LIB_ARC4)),$(LINUX_DIR)/lib/crypto/libarc4.ko)'
UNCOND = '$(LINUX_DIR)/lib/crypto/libarc4.ko'


def rd(p):
    return io.open(p, encoding='utf-8', errors='surrogateescape', newline='\n').read()


def wr(p, s):
    io.open(p, 'w', encoding='utf-8', errors='surrogateescape', newline='\n').write(s)


# 1) kmod-crypto-arc4 成为 libarc4.ko 的唯一（无条件）提供者
cm = 'package/kernel/linux/modules/crypto.mk'
if os.path.isfile(cm):
    s = rd(cm)
    n = s.count(GUARD)
    if n == 1:
        wr(cm, s.replace(GUARD, UNCOND))
        print('[4m] crypto.mk: kmod-crypto-arc4 改为无条件提供 libarc4.ko')
    else:
        print('::warning::[4m] crypto.mk guard count = %d (expect 1)' % n)
else:
    print('::warning::[4m] %s not found' % cm)

# 2)+3) 消费者不再自带 libarc4.ko，只保留 +kmod-crypto-arc4 依赖
for path in ('package/kernel/linux/modules/netsupport.mk',
             'package/kernel/mac80211/Makefile'):
    if not os.path.isfile(path):
        print('::warning::[4m] %s not found' % path)
        continue
    s = rd(path)
    n = s.count(' ' + GUARD)
    if n == 1:
        wr(path, s.replace(' ' + GUARD, ''))
        print('[4m] %s: 移除自带 libarc4.ko（改由 kmod-crypto-arc4 提供）' % path)
    else:
        print('::warning::[4m] %s guard count = %d (expect 1)' % (path, n))
PY_ARC4_OWNER
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

