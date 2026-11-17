#include "moisture.h"

#include <errno.h>
#include <zephyr/device.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

#define GPIO_SENSE       20
#define GPIO_CHARGE      22
#define GPIO_DISCHARGE   24

#define TIMEOUT_US    10000
#define DISCHARGE_HOLD_MS  20
static const struct device *const gpio_port = DEVICE_DT_GET(DT_NODELABEL(gpio0));


static int64_t measure_sensor_us(void)
{

    // Hold the MOS on even if SENSE already reads LOW: LOW does not
    // guarantee that the capacitor has fully discharged.
    gpio_pin_set(gpio_port, GPIO_CHARGE, 0);
    gpio_pin_set(gpio_port, GPIO_DISCHARGE, 1);
    k_msleep(DISCHARGE_HOLD_MS);

    if (gpio_pin_get(gpio_port, GPIO_SENSE) != 0)
    {
        gpio_pin_set(gpio_port, GPIO_DISCHARGE, 0);
        printk("Sensor still HIGH after discharge\n");
        return -1;
    }

    // Release the sensor node before charging it.
    gpio_pin_set(gpio_port, GPIO_DISCHARGE, 0);
    k_busy_wait(10);

    if (gpio_pin_get(gpio_port, GPIO_SENSE) != 0)
    {
        printk("Sensor became HIGH before charging\n");
        return -1;
    }

    // Start charging through 1 MΩ
    uint32_t start_cycles = k_cycle_get_32();
    gpio_pin_set(gpio_port, GPIO_CHARGE, 1);

    while (gpio_pin_get(gpio_port, GPIO_SENSE) == 0)
    {
        int64_t elapsed_us = k_cyc_to_us_floor64((uint32_t)(k_cycle_get_32() - start_cycles));

        if (elapsed_us > TIMEOUT_US)
        {
            gpio_pin_set(gpio_port, GPIO_CHARGE, 0);
            printk("Sensor did not reach HIGH within %d us\n", TIMEOUT_US);
            return -1;
        }

        // Keep microsecond timing; the short timeout bounds this busy wait.
    }

    int64_t charge_time_us = k_cyc_to_us_floor64((uint32_t)(k_cycle_get_32() - start_cycles));

    // Stop charging
    gpio_pin_set(gpio_port, GPIO_CHARGE, 0);

    return charge_time_us;
}

int ping_moisture_sensor(struct moisture_samples *samples)
{
    int result = 0;

    if (samples == NULL)
    {
        return -EINVAL;
    }

    for (int i = 0; i < MOISTURE_SAMPLE_COUNT; ++i)
    {
        samples->elapsed_us[i] = -1;
    }

    if (!device_is_ready(gpio_port))
    {
        printk("GPIO0 controller is not ready\n");
        return -ENODEV;
    }

    if (gpio_pin_configure(gpio_port, GPIO_DISCHARGE, GPIO_OUTPUT_LOW) < 0 ||
        gpio_pin_configure(gpio_port, GPIO_SENSE, GPIO_INPUT) < 0 ||
        gpio_pin_configure(gpio_port, GPIO_CHARGE, GPIO_OUTPUT_LOW) < 0)
    {
        printk("Sensor GPIO configuration failed\n");
        return -EIO;
    }

    for (int i = 0; i < MOISTURE_SAMPLE_COUNT; ++i)
    {
        samples->elapsed_us[i] = measure_sensor_us();

        if (samples->elapsed_us[i] < 0)
        {
            printk("Sensor measurement failed\n");
            result = -EIO;
        }
    }

    return result;
}
