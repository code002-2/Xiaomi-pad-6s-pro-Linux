/*
 * libssc: Library to expose Qualcomm Sensor Core sensors
 * Copyright (C) 2022-2025 Dylan Van Assche
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#ifndef _LIBSSC_CLIENT_H_
#define _LIBSSC_CLIENT_H_

#include <glib.h>
#include <glib/gstdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <gio/gio.h>
#include <libqmi-glib.h>
#include <stdbool.h>
#include "libssc-common-private.h"
#include "libssc-sensor.h"
#include "ssc-common.pb-c.h"

G_BEGIN_DECLS

typedef struct _SSCClient SSCClient;
typedef struct _SSCSensor SSCSensor;

#define SSC_TYPE_CLIENT (ssc_client_get_type())

G_DECLARE_FINAL_TYPE (SSCClient, ssc_client, SSC, CLIENT, GObject);

typedef enum {
	SSC_CLIENT_ERROR_PROTOBUF,
	SSC_CLIENT_ERROR_LOOKUP,
} SSCClientError;

#define SSC_PROCESSOR_APSS		1
#define SSC_SUSPEND_MODE_WAKEUP		0
#define SSC_SENSOR_TYPE_SUID		"suid"
#define SSC_SENSOR_UID_SUID_LOW		0xABABABABABABABABUL
#define SSC_SENSOR_UID_SUID_HIGH	0xABABABABABABABABUL
#define SSC_MSG_REQUEST_SUID		512
#define SSC_MSG_RESPONSE_SUID		768

void
ssc_client_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);

SSCClient *
ssc_client_new_finish (GAsyncResult *res, GError **error);

void
ssc_client_send (SSCClient *self, guint64 uid_high, guint64 uid_low, guint32 message_id, GArray *protobuf, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data); 

gboolean
ssc_client_send_finish (SSCClient *self, GAsyncResult *res, GError **error);

SSCSensor *
ssc_client_get_sensor_by_data_type (SSCClient *self, gchar *data_type);

G_END_DECLS

#endif /* _LIBSSC_CLIENT_H_ */
