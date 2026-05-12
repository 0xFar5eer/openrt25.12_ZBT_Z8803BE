include $(TOPDIR)/rules.mk

PKG_NAME:=zbt-crash-forensics
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=openrt-zbt8803be
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/zbt-crash-forensics
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ZBT crash and reboot forensics for ZBT-Z8803BE
endef

define Package/zbt-crash-forensics/description
  Captures kernel pstore dumps, periodic health snapshots, clean-shutdown
  markers, and a persistent boot-events log under /etc/zbt-crash-logs/
  so unexpected reboots and kernel crashes can be investigated later.
endef

define Build/Compile
endef

define Package/zbt-crash-forensics/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./root/usr/sbin/zbt-crash-forensics $(1)/usr/sbin/zbt-crash-forensics
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/zbt_crash_forensics $(1)/etc/init.d/zbt_crash_forensics
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/49-zbt-crash-forensics $(1)/etc/uci-defaults/49-zbt-crash-forensics
endef

$(eval $(call BuildPackage,zbt-crash-forensics))
