#include "esp_log.h"
#include "driver/gpio.h"
#include "esp_timer.h"
#include "esp_rom_sys.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "MOIST";

#define GPIO_SENSE    GPIO_NUM_32
#define GPIO_CHARGE   GPIO_NUM_14

#define TIMEOUT_US    10000000
#define DISCHARGE_US  5000
#define MAX_MOIST_CHARGE_TIME_US 120
// uint8_t get_moist_perc(int64_t *chargetime);
static int64_t measure_sensor_us(void)
{

    // Actively discharge sensor node through GPIO32
    gpio_set_direction(GPIO_SENSE, GPIO_MODE_OUTPUT);
    gpio_set_level(GPIO_SENSE, 0);
    esp_rom_delay_us(DISCHARGE_US);

    // Release sensor node
    gpio_set_direction(GPIO_SENSE, GPIO_MODE_INPUT);
    gpio_set_pull_mode(GPIO_SENSE, GPIO_FLOATING);
    esp_rom_delay_us(10);

    ESP_LOGI(TAG, "Sense before charging: %d", gpio_get_level(GPIO_SENSE));

    // Start charging through 1 MΩ
    int64_t start_us = esp_timer_get_time();
    gpio_set_level(GPIO_CHARGE, 1);

    while (gpio_get_level(GPIO_SENSE) == 0)
    {
        int64_t elapsed_us = esp_timer_get_time() - start_us;

        if (elapsed_us > TIMEOUT_US)
        {
            gpio_set_level(GPIO_CHARGE, 0);
            return -1;
        }

        // Avoid watchdog reset during long wait
        if (elapsed_us > 1000)
        {
            vTaskDelay(pdMS_TO_TICKS(1));
        }
    }

    int64_t charge_time_us = esp_timer_get_time() - start_us;

    // Stop charging
    gpio_set_level(GPIO_CHARGE, 0);

    return charge_time_us;
}

void app_main(void)
{
    gpio_set_direction(GPIO_CHARGE, GPIO_MODE_OUTPUT);
    gpio_set_level(GPIO_CHARGE, 0);

    while (true)
    {
        int64_t t = measure_sensor_us();

        if (t < 0)
        {
            ESP_LOGE(TAG, "Timeout: sensor did not reach HIGH");
        }
        else
        {
            ESP_LOGI(TAG, "Sensor charged in %lld us", t);
        }

        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

// uint8_t get_moist_perc(int64_t *chargetime){
//     return (uint8_t)((*chargetime * 100) / MAX_MOIST_CHARGE_TIME_US);
// }
