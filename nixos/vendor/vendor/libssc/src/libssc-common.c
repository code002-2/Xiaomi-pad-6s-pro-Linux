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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#include "libssc-common-private.h"

void
ssc_common_dump_protobuf (GArray *protobuf)
{
	GString *str = NULL;
	g_autofree gchar *data = NULL;

	if (protobuf == NULL) {
		g_warning ("Invalid ProtoBuf data!");
		return;
	}

	g_debug ("ProtoBuf data:");
	str = g_string_new ("");
	for (gsize i = 0; i < protobuf->len; i++) {
		guint8 value = g_array_index (protobuf, guint8, i);
		g_string_append_printf (str, "\\x%02x", value); 
	}

	data = g_string_free (str, FALSE);
	g_debug ("%s", data);
}
