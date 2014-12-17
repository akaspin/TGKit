/*
 This Source Code Form is subject to the terms of the Mozilla Public
 License, v. 2.0. If a copy of the MPL was not distributed with this
 file, You can obtain one at http://mozilla.org/MPL/2.0/.
 
 Copyright (c) 2014 nKey.
 */

#ifndef TGKit_tgnet_c_h
#define TGKit_tgnet_c_h

#include <stdbool.h>

struct connection;
typedef long (*socket_function_t)(void *socket, uint8_t *buffer, long buffer_size);
typedef void (*socket_callback_t)(socket_function_t socket_function, void *socket, void *extra);
typedef void (*socket_timer_t)(void *extra);

// TGNet C interface

/**
 * Set the queue where tgnet_dispatch_response will execute.
 */
void tgnet_set_response_queue(void *queue);

/**
 * Call the execute method in the set response queue.
 */
int tgnet_dispatch_response(struct connection *c, int op, int len);

/**
 * Set the callback to be notified when there is data available on the socket stream for reading.
 */
void tgnet_read_callback(const void *socket, socket_callback_t read_cb, void *extra);

/**
 * Set the callback to be notified when the socket stream is ready for writing.
 */
void tgnet_write_callback(const void *socket, socket_callback_t write_cb, void *extra);

/**
 * Request to start being notified when reading is available. Read callback will be called multiple times until socket is closed.
 */
//void tgnet_start_read(const void *socket);

/**
 * Request to receive notification when writing is possible. Write callback will only be called once when socket is ready to write.
 */
void tgnet_request_write(const void *socket);

/**
 * Initialize socket stream connection to host and port and return an opaque tgnet socket pointer.
 */
const void *tgnet_connect (const char *host, uint16_t port);

/**
 * Close a tgnet socket and all associated data, including timers.
 */
void tgnet_close (const void *socket);

/**
 * Disconnect all currently open socket stream connections.
 */
void tgnet_disconnect_all (void);

/**
 * Return opaque pointer to shared tgnet instance.
 */
const void * const tgnet_instance (void);

/**
 * Initialize a one-off timer to be run on the socket. Call tgnet_timer_add with to start the timer. Return -1 on error.
 */
int tgnet_timer_new (const void *_socket, socket_timer_t timer_cb, void *extra);

/**
 * Run the one-off timer after a number of seconds.
 */
void tgnet_timer_add (const void *_socket, int timer_index, long seconds);

/**
 * Cancel and remove the created one-off timer;
 */
void tgnet_timer_del (const void *_socket, int timer_index);

#endif
