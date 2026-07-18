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

#ifndef _LIBSSC_SENSOR_COMPASS_H_
#define _LIBSSC_SENSOR_COMPASS_H_

#include <glib.h>
#include <gio/gio.h>
#include "libssc-sensor.h"

#define SSC_TYPE_SENSOR_COMPASS (ssc_sensor_compass_get_type())

typedef struct _SSCSensorCompass {
	SSCSensor parent;
} SSCSensorCompass;

G_DECLARE_FINAL_TYPE (SSCSensorCompass, ssc_sensor_compass, SSC, SENSOR_COMPASS, SSCSensor);

void		 	 ssc_sensor_compass_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
SSCSensorCompass 	*ssc_sensor_compass_new_finish (GAsyncResult *result, GError **error);
SSCSensorCompass      *ssc_sensor_compass_new_sync (GCancellable *cancellable, GError **error);
void			 ssc_sensor_compass_open (SSCSensorCompass *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_compass_open_finish (SSCSensorCompass *self, GAsyncResult *result, GError **error);
gboolean                 ssc_sensor_compass_open_sync (SSCSensorCompass *self, GCancellable *cancellable, GError **error);
void			 ssc_sensor_compass_close (SSCSensorCompass *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_compass_close_finish (SSCSensorCompass *self, GAsyncResult *result, GError **error);
gboolean                 ssc_sensor_compass_close_sync (SSCSensorCompass *self, GCancellable *cancellable, GError **error);

#endif /* _LIBSSC_SENSOR_COMPASS_H_ */
