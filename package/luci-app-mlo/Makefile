#
# Copyright (C) 2026 openrt-zbt8803be contributors
# SPDX-License-Identifier: Apache-2.0
#
# luci-app-mlo - WiFi 7 Multi-Link Operation configuration for LuCI.
#
# OpenWrt mainline LuCI (luci-mod-network 2026-04) has no first-class
# form field for mld_ap / mld_id, so this app exposes them directly
# on its own page. Hostapd with CONFIG_IEEE80211BE (wpad-openssl or
# wpad-openssl-large) consumes the values.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for WiFi 7 Multi-Link Operation
LUCI_DEPENDS:=+wpad-openssl
LUCI_PKGARCH:=all

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=openrt-zbt8803be

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
