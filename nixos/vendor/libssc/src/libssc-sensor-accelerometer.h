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

#ifndef _LIBSSC_SENSOR_ACCELEROMETER_H_
#define _LIBSSC_SENSOR_ACCELEROMETER_H_

#include <glib.h>
#include <gio/gio.h>
#include "libssc-sensor.h"

#define SSC_TYPE_SENSOR_ACCELEROMETER (ssc_sensor_accelerometer_get_type())

typedef struct _SSCSensorAccelerometer {
	SSCSensor parent;
} SSCSensorAccelerometer;

G_DECLARE_FINAL_TYPE (SSCSensorAccelerometer, ssc_sensor_accelerometer, SSC, SENSOR_ACCELEROMETER, SSCSensor);

void		 	 ssc_sensor_accelerometer_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
SSCSensorAccelerometer 	*ssc_sensor_accelerometer_new_finish (GAsyncResult *result, GError **error);
SSCSensorAccelerometer      *ssc_sensor_accelerometer_new_sync (GCancellable *cancellable, GError **error);
void			 ssc_sensor_accelerometer_open (SSCSensorAccelerometer *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_accelerometer_open_finish (SSCSensorAccelerometer *self, GAsyncResult *result, GError **error);
gboolean                 ssc_sensor_accelerometer_open_sync (SSCSensorAccelerometer *self, GCancellable *cancellable, GError **error);
void			 ssc_sensor_accelerometer_close (SSCSensorAccelerometer *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_accelerometer_close_finish (SSCSensorAccelerometer *self, GAsyncResult *result, GError **error);
gboolean                 ssc_sensor_accelerometer_close_sync (SSCSensorAccelerometer *self, GCancellable *cancellable, GError **error);

#endif /* _LIBSSC_SENSOR_ACCELEROMETER_H_ */
