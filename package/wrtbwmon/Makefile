include $(TOPDIR)/rules.mk

PKG_NAME:=wrtbwmon
PKG_VERSION:=0.36
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=0xFar5eer
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/wrtbwmon
  SECTION:=net
  CATEGORY:=Network
  TITLE:=nftables bandwidth monitor with SQLite history
  DEPENDS:=+firewall4 +nftables-json +sqlite3-cli +python3 +python3-sqlite3
endef

define Package/wrtbwmon/description
  Custom nftables/firewall4 bandwidth monitor with SQLite device history and optional domain tracking.
endef

define Package/wrtbwmon/conffiles
/etc/config/wrtbwmon
/etc/wrtbwmon.conf
endef

define Build/Compile
endef

define Package/wrtbwmon/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) files/usr/sbin/wrtbwmon $(1)/usr/sbin/
	$(INSTALL_BIN) files/usr/sbin/wrtbwmon-control $(1)/usr/sbin/
	$(INSTALL_BIN) files/usr/sbin/wrtbwmon-*.py $(1)/usr/sbin/
	$(INSTALL_DATA) files/usr/sbin/wrtbwmon_nft.py $(1)/usr/sbin/
	$(INSTALL_DIR) $(1)/usr/lib/wrtbwmon
	$(INSTALL_BIN) files/usr/lib/wrtbwmon/*.sh $(1)/usr/lib/wrtbwmon/
	$(INSTALL_DIR) $(1)/usr/lib/wrtbwmon/dns_backends
	$(INSTALL_BIN) files/usr/lib/wrtbwmon/dns_backends/*.sh $(1)/usr/lib/wrtbwmon/dns_backends/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) files/etc/init.d/wrtbwmon $(1)/etc/init.d/wrtbwmon
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) files/etc/hotplug.d/iface/80-wrtbwmon $(1)/etc/hotplug.d/iface/80-wrtbwmon
	$(INSTALL_DIR) $(1)/etc/hotplug.d/firewall
	$(INSTALL_BIN) files/etc/hotplug.d/firewall/50-wrtbwmon $(1)/etc/hotplug.d/firewall/50-wrtbwmon
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) files/etc/config/wrtbwmon $(1)/etc/config/wrtbwmon
	$(INSTALL_CONF) files/etc/wrtbwmon.conf $(1)/etc/wrtbwmon.conf
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	echo '/etc/wrtbwmon/' >  $(1)/lib/upgrade/keep.d/wrtbwmon
	echo '/etc/wrtbwmon.conf' >> $(1)/lib/upgrade/keep.d/wrtbwmon
endef

$(eval $(call BuildPackage,wrtbwmon))
