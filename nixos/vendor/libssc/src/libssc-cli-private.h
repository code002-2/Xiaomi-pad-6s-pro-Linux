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

#ifndef _LIBSSC_CLI_H_
#define _LIBSSC_CLI_H_

#include <stdio.h>
#include <glib.h>
#include <glib/gstdio.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <gio/gio.h>
#include <libqmi-glib.h>
#include "libssc-client-private.h"
#include "libssc-version-private.h"
#include "libssc-sensor.h"
#include "libssc-sensor-proximity.h"
#include "libssc-sensor-light.h"
#include "libssc-sensor-accelerometer.h"
#include "libssc-sensor-magnetometer.h"
#include "libssc-sensor-compass.h"
#include "libssc-sensor-gyroscope.h"

typedef struct {
	GMainLoop *loop;
	gchar *device_str;
	SSCClient *client;
} SSCCli;

#endif /* _LIBSSC_CLI_H_ */
