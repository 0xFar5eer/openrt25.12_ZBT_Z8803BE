include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI WiFi clients dashboard
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+python3 +dropbear +iw +ubus +uci +ip-bridge

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=openrt-zbt8803be

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
