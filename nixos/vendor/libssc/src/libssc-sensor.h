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

#ifndef _LIBSSC_SENSOR_H_
#define _LIBSSC_SENSOR_H_

#include <glib.h>
#include <gio/gio.h>

G_BEGIN_DECLS

typedef struct _SSCSensor SSCSensor;
typedef struct _SSCClient SSCClient;

#define SSC_TYPE_SENSOR (ssc_sensor_get_type())

G_DECLARE_DERIVABLE_TYPE (SSCSensor, ssc_sensor, SSC, SENSOR, GObject);

typedef enum {
	SSC_SENSOR_ERROR_UNAVAILABLE,
	SSC_SENSOR_ERROR_SAMPLE_RATE_UNAVAILABLE,
	SSC_SENSOR_ERROR_NO_SERVICE,
} SSCSensorError;

GQuark ssc_sensor_error_quark(void);

#define SSC_SENSOR_UID_LOW "uid-low"
#define SSC_SENSOR_UID_HIGH "uid-high"
#define SSC_SENSOR_NAME "name"
#define SSC_SENSOR_VENDOR "vendor"
#define SSC_SENSOR_DATA_TYPE "data-type"
#define SSC_SENSOR_STREAM_TYPE "stream-type"
#define SSC_SENSOR_AVAILABLE "available"
#define SSC_SENSOR_SAMPLE_RATE "sample-rate"
#define SSC_SENSOR_CLIENT "client"

void		 ssc_sensor_new (gchar *data_type, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
SSCSensor 	*ssc_sensor_new_finish (GAsyncResult *result, GError **error);
void		 ssc_sensor_open (SSCSensor *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean	 ssc_sensor_open_finish (SSCSensor *self, GAsyncResult *result, GError **error);
void		 ssc_sensor_close (SSCSensor *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean	 ssc_sensor_close_finish (SSCSensor *self, GAsyncResult *result, GError **error);

struct _SSCSensorClass {
	GObjectClass parent_class;

	void (*open) (SSCSensor *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
	gboolean (*open_finish) (SSCSensor *self, GAsyncResult *result, GError **error);
	void (*close) (SSCSensor *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
	gboolean (*close_finish) (SSCSensor *self, GAsyncResult *result, GError **error);
};

G_END_DECLS

#endif /* _LIBSSC_SENSOR_H_ */
