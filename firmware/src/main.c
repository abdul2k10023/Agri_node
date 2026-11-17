#include <errno.h>
#include <inttypes.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/uart.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>
#include <zephyr/sys/util.h>
#include <zephyr/version.h>

#include "thread_demo.h"
#include "moisture.h"

BUILD_ASSERT(DT_NODE_HAS_COMPAT(DT_CHOSEN(zephyr_console), zephyr_cdc_acm_uart),
             "This application requires a USB CDC ACM console");

static const struct gpio_dt_spec led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

int main(void)
{
    const struct device *console = DEVICE_DT_GET(DT_CHOSEN(zephyr_console));
    bool terminal_was_open = false;
    uint32_t ticks = 0;

    if (!gpio_is_ready_dt(&led)) {
        printk("LED controller is not ready\n");
        return -ENODEV;
    }

    int err = gpio_pin_configure_dt(&led, GPIO_OUTPUT_INACTIVE);

    if (err < 0) {
        printk("LED configuration failed: %d\n", err);
        return err;
    }

    int thread_error = thread_demo_init();

    for (;;) {
        uint32_t dtr = 0;
        bool terminal_open = device_is_ready(console) &&
            uart_line_ctrl_get(console, UART_LINE_CTRL_DTR, &dtr) == 0 && dtr;

        err = gpio_pin_toggle_dt(&led);
        if (terminal_open) {
            if (!terminal_was_open) {
                printk("\nMoist Node: Zephyr %s\n", KERNEL_VERSION_STRING);
                printk("Board: %s | UF2 application | USB console ready\n",
                       CONFIG_BOARD_TARGET);
                printk("Thread demo: same firmware on both boards; UDP port 4242\n");
                if (thread_error != 0) {
                    printk("Thread demo initialization failed: %d\n", thread_error);
                }
            }
            if (ticks % 4U == 0U || !terminal_was_open) {
                printk("uptime=%" PRId64 " ms, LED=%s\n", k_uptime_get(),
                       err < 0 ? "GPIO error" : "heartbeat running");
            }
        }
        
        if (thread_error == 0) {
            thread_demo_poll(terminal_open);
        }
        terminal_was_open = terminal_open;
        ++ticks;
        k_sleep(K_MSEC(2000));
    }
}

