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

#ifndef _LIBSSC_SENSOR_PROXIMITY_H_
#define _LIBSSC_SENSOR_PROXIMITY_H_

#include <glib.h>
#include <gio/gio.h>
#include "libssc-sensor.h"

#define SSC_TYPE_SENSOR_PROXIMITY (ssc_sensor_proximity_get_type())

/* 
 * xiaomi-davinci's proximity message contains bytes that appear to be a C struct.
 * Judging by the placing of the zeroes in the payloads, the struct seems to contain a bunch of 32-bit floats.
 * FIXME: Figure out what all the fields are.
 */
typedef struct {
	/* 1.0 if NEAR, else 0.0 */
	float near;
	/* Increases with proximity to the sensor */
	float coverness;
	/* 
	 * Calibration offset, unknown use
	 * Note: prox_offset_h is definitely not included in the struct
	 */
	float prox_offset_l;
	/* Sometimes 0.0, rarely -1.0 */
	float unknown1;
	/* Apparently always 0.0 */
	float unknown2;
	/* Apparently always 0.0 */
	float unknown3;
	/* If NEAR, coverness value right on the sensor; if FAR, this is the near threshold */
	float near_state_range_min;
	/* If NEAR, this is the far threshold; if FAR, it is 1.0 */
	float near_state_range_max;
	/* Coverness threadshold for NEAR */
	float near_threshold;
	/* Coverness threshold for FAR */
	float far_threshold;
	/* Apparently always 0.0, likely reserved for future use */
	float reserved1;
	/* Apparently always 0.0 */
	float reserved2;
	/* Apparently always 0.0 */
	float reserved3;
	/* Apparently always 0.0 */
	float reserved4;
	/* Apparently always 0.0 */
	float reserved5;
	/* Apparently always 0.0 */
	float reserved6;
} ProximityDataDavinci;

typedef struct _SSCSensorProximity {
	SSCSensor parent;
} SSCSensorProximity;

G_DECLARE_FINAL_TYPE (SSCSensorProximity, ssc_sensor_proximity, SSC, SENSOR_PROXIMITY, SSCSensor);

void		 	 ssc_sensor_proximity_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
SSCSensorProximity 	*ssc_sensor_proximity_new_finish (GAsyncResult *result, GError **error);
SSCSensorProximity 	*ssc_sensor_proximity_new_sync (GCancellable *cancellable, GError **error);
void			 ssc_sensor_proximity_open (SSCSensorProximity *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_proximity_open_finish (SSCSensorProximity *self, GAsyncResult *result, GError **error);
gboolean		 ssc_sensor_proximity_open_sync (SSCSensorProximity *self, GCancellable *cancellable, GError **error);
void			 ssc_sensor_proximity_close (SSCSensorProximity *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data);
gboolean		 ssc_sensor_proximity_close_finish (SSCSensorProximity *self, GAsyncResult *result, GError **error);
gboolean		 ssc_sensor_proximity_close_sync (SSCSensorProximity *self, GCancellable *cancellable, GError **error);

#endif /* _LIBSSC_SENSOR_PROXIMITY_H_ */
