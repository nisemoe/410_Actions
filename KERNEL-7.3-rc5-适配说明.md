# Linux 7.3-rc5 适配说明（msm89xx / MSM8916 / ufi-wf2）

目标机型 DTS：`scripts/msm89xx/target/linux/msm89xx/dts/msm8916-xinxun-wf2.dts`
（`model = "ufi-wf2 4G Modem Stick"`，`compatible = "xinxun,wf2", "qcom,msm8916"`，
对应 image 里的 `DEVICE_openstick-wf2`）。

适配采取 **opt-in（可选开启）** 方式：默认仍是 6.18，只有使用 `config/wf2-73.config`
编译时才会切到 7.3-rc5，现有机型配置不受影响。

---

## 1. 改动清单

| 文件 | 改动 | 说明 |
|---|---|---|
| `scripts/msm89xx/target/linux/generic/kernel-7.3` | 新增 | 版本号 `LINUX_VERSION-7.3 = -rc5`，OpenWrt 没有 7.3 的版本定义文件，必须自己提供 |
| `scripts/msm89xx/target/linux/generic/config-7.3` | 构建时生成 | `diy-part1.sh` 自动用上游最新的 `generic/config-x.y` 复制一份 |
| `scripts/msm89xx/target/linux/msm89xx/config-7.3` | 新增（由 `config-6.18` 复制） | 目标层内核配置 |
| `scripts/msm89xx/target/linux/msm89xx/patches-7.3/` | 新增（由 `patches-6.18` 复制） | wcn36xx 并发补丁 + qcom-memshare |
| `scripts/msm89xx/target/linux/msm89xx/Makefile` | `FEATURES` 加 `testing-kernel`；新增 `KERNEL_TESTING_PATCHVER:=7.3` | 走 OpenWrt 的 testing-kernel 机制，`.config` 里 `CONFIG_TESTING_KERNEL=y` 才生效 |
| `scripts/msm89xx/package/kernel/linux/modules/netdevices.mk` | `kmod-rpmsg-wwan-ctrl` 的 `DEPENDS` 追加 `\|\|LINUX_7_3` | 原来写成 `@LINUX_6_1\|\|...\|\|LINUX_6_18`，7.3 下会被 defconfig **静默丢弃**，导致丢掉 WWAN 控制口 |
| `config/wf2-73.config` | 新增 | `wf2.config` + `CONFIG_LINUX_7_3=y` + `CONFIG_TESTING_KERNEL=y` |
| `.github/workflows/Build_imm_高通_8916_73.yml` | 新增 | 7.3 专用构建流程（矩阵 `wf2-73`） |
| `diy-part1.sh` | 追加 7.3 准备/校验段 | 生成 generic config-7.3、校验必需文件 |

### 关于 `-rc` 内核的下载（重要）

`include/kernel.mk` 里对版本号含 `-rc` 的情况有专门分支：

```make
ifneq (,$(findstring -rc,$(LINUX_VERSION)))
    LINUX_SOURCE:=linux-$(LINUX_VERSION).tar.gz     # 注意是 .tar.gz 不是 .tar.xz
    LINUX_SITE:=https://git.kernel.org/torvalds/t   # rc 包只在 git.kernel.org
```

即下载 `https://git.kernel.org/torvalds/t/linux-7.3-rc5.tar.gz`。
已实测：该地址 200 可下载（会 301 到 git.kernel.org 的 snapshot），
而 `cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.3-rc5.tar.xz` 是 404（rc 包不在 cdn 上）。

`kernel-7.3` 里**故意不写 `LINUX_KERNEL_HASH-7.3-rc5`**：`kernel-version.mk` 会退化成
`LINUX_KERNEL_HASH?=x`，即跳过校验（rc 包没有官方发布的 sha256 清单）。
想固定校验和的话，编译一次后 `sha256sum dl/linux-7.3-rc5.tar.gz`，把值写成
`LINUX_KERNEL_HASH-7.3-rc5 = <sha256>` 加进该文件即可。

升到更新的 rc（如 rc6）时，只需改 `generic/kernel-7.3` 里的 `-rc5`。

---

## 2. 已经验证过的部分

拿 v7.3-rc5 源码实测：

1. **补丁可打**：`patches-7.3/` 里的 6 个补丁对 `linux-7.3-rc5` 全部 `patch -p1` 成功
   - 995 / 997 / 998 / 999（wcn36xx）：main.c、smd.c  hunks 命中有 offset/fuzz，quilt 同样接受
   - `add-qcom-memshare.patch`（新增 `include/dt-bindings/soc/qcom,memshare.h`，7.3 尚无此文件）
   - `soc-qcom-Add-memshare-service.patch`（Kconfig/Makefile/新增 3 个文件，Kconfig hunk fuzz 2 通过）
2. **kmod 依赖的内核符号在 7.3 里都还在**：
   `QCOM_MDT_LOADER`、`QCOM_PIL_INFO`、`QCOM_RPROC_COMMON`、`QCOM_WCNSS_PIL`、
   `QCOM_WCNSS_CTRL`、`QCOM_Q6V5_COMMON`、`QCOM_Q6V5_MSS`、`QCOM_BAM_DMUX`、
   `RPMSG_WWAN_CTRL`（都在 `drivers/remoteproc/Kconfig`、`drivers/soc/qcom/Kconfig`、`drivers/net/wwan/Kconfig`）
3. **DTS 用到的 dt-bindings 在 7.3 里都还在**：`LED_COLOR_ID_RED/GREEN/BLUE`、
   `LED_FUNCTION_POWER/WLAN/WAN`、`linux,extcon-usb-gpio`（驱动文件仍在）。
   → **`msm8916-xinxun-wf2.dts` 不需要为 7.3 改任何一行**：
   它 include 的 `msm8916-mifi.dtsi` / `msm8916.dtsi` 都来自本仓库 `dts/` 目录
   （`DEVICE_DTS_DIR := ../dts`），编译时用的是仓库自带的 dtsi，不依赖内核版本；
   `CLUSTER_PD` / `CPU_SLEEP_0` / `CLUSTER_RET` 这些 label 也都在仓库自带的
   `msm8916.dtsi` 里，7.3 的 cpuidle 变化不会影响它。

---

## 3. 怎么编

- GitHub Actions：手动运行 **Build_imm_高通_8916_73**（矩阵 `wf2-73`，配置 `config/wf2-73.config`）。
- 本地/自建 runner：
  ```bash
  git clone https://github.com/immortalwrt/immortalwrt -b master openwrt
  cd openwrt && <本仓库>/diy-part1.sh && <本仓库>/diy-part2.sh
  cp <本仓库>/config/wf2-73.config .config && make defconfig
  make -j$(nproc)
  ```
  编译日志里应看到 `linux-7.3-rc5.tar.gz` 的下载，模块目录为 `lib/modules/7.3-rc5`。

---

## 4. 风险点与回退方案

### 4.1 最大风险：`kmod-wcn36xx` 来自 mac80211 backports

`kmod-wcn36xx` 不是内核内建模块，而是 `package/kernel/mac80211` 用
`openwrt/backports` 的 **`backports-v7.2`** 源码编译出来的（见 ath.mk：
`FILES:=$(PKG_BUILD_DIR)/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko`）。
拿 7.2 的 backports 去编 7.3-rc5 的内核头文件，7.2→7.3 之间若有 mac80211/ath API 变化就会编译失败。
（注意：仓库里 `patches-7.3/*.patch` 打的是**内核树**里的 wcn36xx，而内核树里
`CONFIG_WCN36XX` 并没有开，所以这些补丁只是"保险"，真正生效的 wcn36xx 是 backports 那份；
backports 的补丁在 `package/kernel/mac80211/patches/ath/9x-wcn36xx-*.patch`。）

**回退方案（Plan B）：改用内核内建 wcn36xx**

1. `target/linux/msm89xx/config-7.3` 里加一行：
   ```
   CONFIG_WCN36XX=m
   ```
2. 把 `package/kernel/mac80211/ath.mk` 里 wcn36xx 的 FILES 指向内核树：
   ```
   FILES:=$(LINUX_DIR)/drivers/net/wireless/ath/wcn36xx/wcn36xx.ko
   ```
   （并去掉 `config-$(CONFIG_TARGET_msm89xx) += WCN36XX`，避免 backports 再编一份）
3. 这样用的就是 `patches-7.3` 打过补丁的内核内建驱动（已实测补丁可打）。

### 4.2 generic 层的 backport/hack/pending 补丁缺失

7.3 没有 `target/linux/generic/{backport,hack,pending}-7.3` 目录。
按 `include/target.mk`，目录不存在时变量名退化成 `generic/backport`（不存在），
而 `include/quilt.mk` 的 `PatchDir/Default` 有 `[ -d "$(2)" ]` 判断，缺目录**不会报错**，
只是不打这些补丁。7.3 比 6.18 新，backport 类补丁本就不需要；hack 类补丁若上游
OpenWrt 依赖它做某些特性，可能表现为个别功能差异——编译报错时按报错点补对应补丁即可。

### 4.3 内核配置是 6.18 的复制版

`config-7.3`（目标层）与 `generic/config-7.3` 都是从 6.18 复制来的。
内核构建阶段会跑 `olddefconfig`：7.3 里已删除的符号被丢弃，新增符号取默认值。
可能出现个别功能开关与 6.18 不同。若某功能没了，用 `make kernel_menuconfig` 复核
（或把 6.18 的 `.config` 与 `build_dir/.../linux-7.3-rc5/.config` 做 diff 对比）。

### 4.4 rc 内核本身

7.3-rc5 是主线候选版，尚未发布稳定版；ntp/无线/调制解调器相关行为可能与 6.18 有差异。
建议先出 `boot.img` + `system.img` 用线刷（README 的 flash.zip 流程）验证，
确认能开机、`wwan0`/`wlan0` 正常后再日常使用。

---

## 5. 想让 7.3 成为默认内核（而不是 testing 可选）

把 `scripts/msm89xx/target/linux/msm89xx/Makefile` 改成：

```make
KERNEL_PATCHVER:=7.3
```

并删掉 `KERNEL_TESTING_PATCHVER` 与 `FEATURES` 里的 `testing-kernel`，
`.config` 里去掉 `CONFIG_TESTING_KERNEL=y`、保留 `CONFIG_LINUX_7_3=y` 即可。
此时所有走本 target 的机型配置都会用 7.3-rc5。
