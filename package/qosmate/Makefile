include $(TOPDIR)/rules.mk

PKG_NAME:=qosmate
PKG_VERSION:=0.5.48
PKG_RELEASE:=1

PKG_MAINTAINER:=Markus Hütter <mh@hudra.net>
PKG_LICENSE:=GPL-3.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/qosmate
  SECTION:=net
  CATEGORY:=Base system
  TITLE:=QoSmate - Quality of Service management tool
  DEPENDS:=+kmod-sched +ip-full +kmod-veth +tc-full +kmod-netem +kmod-sched-ctinfo +kmod-ifb +kmod-sched-cake +kmod-sched-red +luci-lib-jsonc +lua +jq +coreutils-sleep
endef

define Package/qosmate/description
  QoSmate is a Quality of Service management tool for OpenWrt
endef

define Build/Prepare
endef

define Build/Compile
endef

define Package/qosmate/conffiles
/etc/config/qosmate
/etc/qosmate.d/qosmate-defaults
endef

define Package/qosmate/install
	$(INSTALL_DIR) $(1)/etc
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DIR) $(1)/etc/qosmate.d
	$(INSTALL_DIR) $(1)/usr/lib/tc

	$(INSTALL_BIN) ./etc/qosmate.sh $(1)/etc/
	$(INSTALL_BIN) ./etc/qosmate-autorate.sh $(1)/etc/
	$(INSTALL_BIN) ./etc/qosmate-autorate-tc.sh $(1)/etc/
	$(INSTALL_BIN) ./etc/init.d/qosmate $(1)/etc/init.d/
	$(INSTALL_BIN) ./etc/init.d/qosmate-autorate $(1)/etc/init.d/
	$(INSTALL_CONF) ./etc/hotplug.d/iface/20-qosmate-hotplug $(1)/etc/hotplug.d/iface/
	$(INSTALL_CONF) ./etc/config/qosmate $(1)/etc/config/
	$(INSTALL_CONF) ./etc/config/qosmate $(1)/etc/qosmate.d/qosmate-defaults
	$(INSTALL_DATA) ./usr/lib/tc/*.dist $(1)/usr/lib/tc/
endef

$(eval $(call BuildPackage,qosmate))
