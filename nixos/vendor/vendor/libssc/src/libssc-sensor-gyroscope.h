/*
 * libssc: Library to expose Qualcomm Sensor Core sensors
 * Copyright (C) 2025 Vasiliy Doylov <nekodevelopper@gmail.com>
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

#ifndef _LIBSSC_SENSOR_GYROSCOPE_H_
#define _LIBSSC_SENSOR_GYROSCOPE_H_

#include <glib.h>
#include <gio/gio.h>
#include "libssc-sensor.h"

#define SSC_TYPE_SENSOR_GYROSCOPE (ssc_sensor_gyroscope_get_type())

typedef struct _SSCSensorGyroscope {
	SSCSensor parent;
} SSCSensorGyroscope;

G_DECLARE_FINAL_TYPE (SSCSensorGyroscope, ssc_sensor_gyroscope, SSC, SENSOR_GYROSCOPE, SSCSensor);

void		 	 ssc_sensor_gyroscope_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
SSCSensorGyroscope 	*ssc_sensor_gyroscope_new_finish (GAsyncResult *result, GError **error);
SSCSensorGyroscope      *ssc_sensor_gyroscope_new_sync (GCancellable *cancellable, GError **error);
void			 ssc_sensor_gyroscope_open (SSCSensorGyroscope *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_gyroscope_open_finish (SSCSensorGyroscope *self, GAsyncResult *result, GError **error);
gboolean                 ssc_sensor_gyroscope_open_sync (SSCSensorGyroscope *self, GCancellable *cancellable, GError **error);
void			 ssc_sensor_gyroscope_close (SSCSensorGyroscope *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_gyroscope_close_finish (SSCSensorGyroscope *self, GAsyncResult *result, GError **error);
gboolean                 ssc_sensor_gyroscope_close_sync (SSCSensorGyroscope *self, GCancellable *cancellable, GError **error);

#endif /* _LIBSSC_SENSOR_GYROSCOPE_H_ */
