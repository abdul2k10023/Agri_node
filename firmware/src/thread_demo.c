#include "thread_demo.h"

#include <errno.h>
#include <inttypes.h>
#include <string.h>

#include <openthread.h>
#include <openthread/ip6.h>
#include <openthread/link.h>
#include <openthread/thread.h>
#include <openthread/udp.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/atomic.h>
#include <zephyr/sys/printk.h>

#define DEMO_PORT 4242
#define DEMO_INTERVAL_MS 6000
#define DEMO_PAYLOAD_SIZE 80

struct received_message {
    otIp6Address peer;
    char text[DEMO_PAYLOAD_SIZE];
};

K_MSGQ_DEFINE(receive_queue, sizeof(struct received_message), 8, 4);

static otInstance *instance;
static otUdpSocket socket;
static otIp6Address destination;
static char node_id[17];
static atomic_t receive_count;
static atomic_t dropped_count;
static uint32_t sequence;
static uint32_t transmit_count;
static uint32_t transmit_errors;
static int64_t next_send;
static int64_t next_status;
static otDeviceRole previous_role = OT_DEVICE_ROLE_DISABLED;
static bool terminal_was_open;

/* Runs in OpenThread's context: copy data, then let main() print it later. */
static void receive_message(void *context, otMessage *message, const otMessageInfo *info)
{
    struct received_message received = { .peer = info->mPeerAddr };
    uint16_t offset = otMessageGetOffset(message);
    uint16_t length = otMessageGetLength(message) - offset;

    ARG_UNUSED(context);
    if (length == 0 || length >= sizeof(received.text)) {
        atomic_inc(&dropped_count);
        return;
    }
    if (otMessageRead(message, offset, received.text, length) != length) {
        atomic_inc(&dropped_count);
        return;
    }
    /* Ignore a local multicast copy if the stack ever delivers one. */
    if (length >= 17 && strncmp(received.text, node_id, 16) == 0 &&
        received.text[16] == ' ') {
        return;
    }
    if (k_msgq_put(&receive_queue, &received, K_NO_WAIT) != 0) {
        atomic_inc(&dropped_count);
        return;
    }
    atomic_inc(&receive_count);
}

int thread_demo_init(void)
{
    otSockAddr local = { .mPort = DEMO_PORT };
    otError error;

    instance = openthread_get_default_instance();
    if (instance == NULL) {
        return -ENODEV;
    }

    openthread_mutex_lock();
    const otExtAddress *address = otLinkGetExtendedAddress(instance);

    for (size_t i = 0; i < sizeof(address->m8); ++i) {
        snprintk(&node_id[i * 2], 3, "%02x", address->m8[i]);
    }
    error = otIp6AddressFromString("ff03::1", &destination);
    if (error == OT_ERROR_NONE) {
        error = otUdpOpen(instance, &socket, receive_message, NULL);
    }
    if (error == OT_ERROR_NONE) {
        error = otUdpBind(instance, &socket, &local, OT_NETIF_THREAD_INTERNAL);
        if (error != OT_ERROR_NONE) {
            (void)otUdpClose(instance, &socket);
        }
    }
    openthread_mutex_unlock();
    return error == OT_ERROR_NONE ? 0 : -EIO;
}

/* Caller holds OpenThread's mutex. Success means queued, not delivered. */
static otError send_message(void)
{
    char payload[DEMO_PAYLOAD_SIZE];
    otMessageInfo info = {
        .mPeerAddr = destination,
        .mPeerPort = DEMO_PORT,
        .mHopLimit = 64,
    };
    otMessage *message = otUdpNewMessage(instance, NULL);
    otError error;

    if (message == NULL) {
        return OT_ERROR_NO_BUFS;
    }
    int length = snprintk(payload, sizeof(payload), "%s seq=%" PRIu32 " hello",
                         node_id, ++sequence);

    error = otMessageAppend(message, payload, length);
    if (error == OT_ERROR_NONE) {
        error = otUdpSend(instance, &socket, message, &info);
    }
    if (error != OT_ERROR_NONE) {
        otMessageFree(message);
    }
    return error;
}

void thread_demo_poll(bool terminal_open)
{
    struct received_message received;
    otIp6Address local_address;
    otDeviceRole role;
    otError send_error = OT_ERROR_NONE;
    int64_t now = k_uptime_get();
    bool attempted_send = false;
    char address_text[OT_IP6_ADDRESS_STRING_SIZE];

    openthread_mutex_lock();
    role = otThreadGetDeviceRole(instance);
    local_address = *otThreadGetMeshLocalEid(instance);
    bool attached = role == OT_DEVICE_ROLE_CHILD || role == OT_DEVICE_ROLE_ROUTER ||
                    role == OT_DEVICE_ROLE_LEADER;

    if (attached && now >= next_send) {
        attempted_send = true;
        send_error = send_message();
        next_send = now + DEMO_INTERVAL_MS;
    }
    openthread_mutex_unlock();

    if (attempted_send) {
        if (send_error == OT_ERROR_NONE) {
            ++transmit_count;
        } else {
            ++transmit_errors;
        }
        if (terminal_open) {
            printk("Thread TX seq=%" PRIu32 " %s (error=%d)\n", sequence,
                   send_error == OT_ERROR_NONE ? "queued" : "failed", send_error);
        }
    }

    while (k_msgq_get(&receive_queue, &received, K_NO_WAIT) == 0) {
        if (terminal_open) {
            otIp6AddressToString(&received.peer, address_text, sizeof(address_text));
            printk("Thread RX from %s: %s\n", address_text, received.text);
        }
    }

    if (terminal_open && (!terminal_was_open || role != previous_role || now >= next_status)) {
        otIp6AddressToString(&local_address, address_text, sizeof(address_text));
        printk("Thread node=%s role=%s address=%s\n", node_id,
               otThreadDeviceRoleToString(role), address_text);
        printk("Thread totals: TX=%" PRIu32 " RX=%ld errors=%" PRIu32 " dropped=%ld\n",
               transmit_count, (long)atomic_get(&receive_count), transmit_errors,
               (long)atomic_get(&dropped_count));
        next_status = now + DEMO_INTERVAL_MS;
    }
    previous_role = role;
    terminal_was_open = terminal_open;
}
