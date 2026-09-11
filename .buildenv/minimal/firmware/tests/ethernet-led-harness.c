/* MDIO simulation for the production Ethernet LED backport. */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <errno.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
#define BIT(n) (1UL << (n))
#define GENMASK(h, l) ((~0UL << (l)) & (~0UL >> (63 - (h))))
#define MDIO_MMD_VEND2 31
enum led_brightness { LED_OFF = 0, LED_ON = 1 };
enum {
    TRIGGER_NETDEV_LINK, TRIGGER_NETDEV_LINK_10, TRIGGER_NETDEV_LINK_100,
    TRIGGER_NETDEV_LINK_1000, TRIGGER_NETDEV_LINK_2500,
    TRIGGER_NETDEV_FULL_DUPLEX, TRIGGER_NETDEV_HALF_DUPLEX,
    TRIGGER_NETDEV_RX, TRIGGER_NETDEV_TX
};
struct phy_device;
struct phy_driver {
    int (*led_hw_control_get)(struct phy_device *, u8, unsigned long *);
};
struct phy_device { void *priv; struct phy_driver *drv; };
static u16 registers[256];
static int mdio_error;
static int phy_read_mmd(struct phy_device *p, int mmd, int reg)
{
    return mdio_error ? -EIO : registers[reg];
}
static int phy_write_mmd(struct phy_device *p, int mmd, int reg, u16 value)
{
    if (mdio_error) return -EIO;
    registers[reg] = value;
    return 0;
}
static int phy_modify_mmd(struct phy_device *p, int mmd, int reg, u16 mask, u16 value)
{
    return phy_write_mmd(p, mmd, reg, (registers[reg] & ~mask) | value);
}
static bool test_bit(unsigned bit, const unsigned long *p) { return !!(*p & BIT(bit)); }
static void set_bit(unsigned bit, unsigned long *p) { *p |= BIT(bit); }
static void clear_bit(unsigned bit, unsigned long *p) { *p &= ~BIT(bit); }
static bool test_and_set_bit(unsigned bit, unsigned long *p) { bool v = test_bit(bit, p); set_bit(bit, p); return v; }
static bool test_and_clear_bit(unsigned bit, unsigned long *p) { bool v = test_bit(bit, p); clear_bit(bit, p); return v; }
/* HEADER */
/* PRIVATE */
/* LIBRARY */
/* CALLBACKS */

int main(void)
{
    struct mtk_i2p5ge_phy_priv priv = { .fw_loaded = true };
    struct phy_driver driver = { .led_hw_control_get = mt7988_2p5ge_led_hw_control_get };
    struct phy_device phy = { .priv = &priv, .drv = &driver };
    unsigned long rules = BIT(TRIGGER_NETDEV_LINK) | BIT(TRIGGER_NETDEV_RX) | BIT(TRIGGER_NETDEV_TX);
    unsigned long readback = 0, on = 100, off = 100;
    assert(offsetof(struct mtk_i2p5ge_phy_priv, leds) == 0);
    registers[MTK_PHY_LED0_ON_CTRL] = MTK_PHY_LED_ON_ENABLE | MTK_PHY_LED_ON_POLARITY;
    assert(mt7988_2p5ge_led_hw_is_supported(&phy, 0, rules) == 0);
    assert(mt7988_2p5ge_led_hw_control_set(&phy, 0, rules) == 0);
    assert((registers[MTK_PHY_LED0_ON_CTRL] & MTK_2P5GPHY_LED_ON_SET) == MTK_2P5GPHY_LED_ON_SET);
    assert(registers[MTK_PHY_LED0_ON_CTRL] & MTK_PHY_LED_ON_ENABLE);
    assert(registers[MTK_PHY_LED0_ON_CTRL] & MTK_PHY_LED_ON_POLARITY);
    assert(registers[MTK_PHY_LED0_BLINK_CTRL] == (MTK_2P5GPHY_LED_RX_BLINK_SET | MTK_2P5GPHY_LED_TX_BLINK_SET));
    assert(mt7988_2p5ge_led_hw_control_get(&phy, 0, &readback) == 0);
    assert((readback & rules) == rules);
    assert(mt7988_2p5ge_led_hw_control_set(&phy, 0, BIT(TRIGGER_NETDEV_TX)) == 0);
    assert(registers[MTK_PHY_LED0_BLINK_CTRL] == (BIT(0) | BIT(2) | BIT(4) | BIT(10)));
    assert(mt7988_2p5ge_led_hw_control_set(&phy, 0, BIT(TRIGGER_NETDEV_RX)) == 0);
    assert(registers[MTK_PHY_LED0_BLINK_CTRL] == (BIT(1) | BIT(3) | BIT(5) | BIT(11)));
    assert(mt7988_2p5ge_led_brightness_set(&phy, 0, LED_OFF) == 0);
    assert(!(registers[MTK_PHY_LED0_ON_CTRL] & MTK_2P5GPHY_LED_ON_MASK));
    assert(registers[MTK_PHY_LED0_BLINK_CTRL] == 0);
    assert(mt7988_2p5ge_led_brightness_set(&phy, 0, LED_ON) == 0);
    assert(registers[MTK_PHY_LED0_ON_CTRL] & MTK_PHY_LED_ON_FORCE_ON);
    assert(mt7988_2p5ge_led_blink_set(&phy, 0, &on, &off) == 0);
    assert(registers[MTK_PHY_LED0_BLINK_CTRL] == MTK_PHY_LED_BLINK_FORCE_BLINK);
    assert(priv.fw_loaded); /* LED writes must not corrupt the firmware cache. */
    assert(mt7988_2p5ge_led_hw_is_supported(&phy, 2, rules) == -EINVAL);
    assert(mt7988_2p5ge_led_hw_is_supported(&phy, 0, BIT(30)) == -EOPNOTSUPP);
    mdio_error = 1;
    assert(mt7988_2p5ge_led_hw_control_set(&phy, 0, rules) == -EIO);
    puts("Ethernet LED C checks passed: link, RX/TX, 2.5G, user triggers, polarity and firmware-cache isolation");
    return 0;
}
