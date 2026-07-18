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

#include <math.h>
#include "libssc-client-private.h"
#include "libssc-common-private.h"
#include "ssc-sensor-rotationvector.pb-c.h"
#include "libssc-sensor-compass.h"

enum {
	SIGNAL_MEASUREMENT,
	N_SIGNALS
};
static guint signals[N_SIGNALS];

typedef struct _SSCSensorCompassPrivate {
	guint report_id;
} SSCSensorCompassPrivate;

G_DEFINE_TYPE_WITH_CODE (SSCSensorCompass, ssc_sensor_compass, SSC_TYPE_SENSOR,
			 G_ADD_PRIVATE (SSCSensorCompass))

typedef struct {
	GAsyncResult *result;
	GMainLoop *loop;
} SyncContext;

static void
sync_cb (GObject *source, GAsyncResult *result, gpointer user_data)
{
	SyncContext *ctx = user_data;

	ctx->result = g_object_ref (result);
	g_main_loop_quit (ctx->loop);
}

typedef struct {
	SSCSensorCompass *sensor;
	gfloat azimuth;
} SignalContext;

static void
signal_context_free (SignalContext *ctx)
{
	g_slice_free (SignalContext, ctx);
}

/*****************************************************************************/
static gfloat
calculate_azimuth (gfloat x, gfloat y, gfloat z, gfloat w)
{
	gfloat q0 = w;
	gfloat q1 = x;
	gfloat q2 = y;
	gfloat q3 = z;
	gfloat q1_q2;
	gfloat q3_q0;
	gfloat sq_q1;
	gfloat sq_q3;
	gfloat r1;
	gfloat r4;
	gfloat azimuth;

	q1_q2 = 2 * q1 * q2;
	q3_q0 = 2 * q3 * q0;
	sq_q1 = 2 * q1 * q1;
	sq_q3 = 2 * q3 * q3;

	r1 = q1_q2 - q3_q0;
	r4 = 1 - sq_q1 - sq_q3;
	azimuth = atan2(r1, r4);

	azimuth = azimuth * 180 / M_PI;
	if (azimuth < 0.0)
		azimuth = azimuth + 360.0;

	return azimuth;
}

/*****************************************************************************/

static gboolean
emit_signal (gpointer user_data) {
	SignalContext *ctx = user_data;

	g_signal_emit (ctx->sensor, signals[SIGNAL_MEASUREMENT], 0, ctx->azimuth);

	return G_SOURCE_REMOVE;
}

static void
report_received (SSCClient *self, guint32 msg_id, guint64 uid_high, guint64 uid_low, GArray *buf, gpointer user_data)
{
	SscRotationvectorResponse *msg = NULL;
	SSCSensorCompass *sensor = SSC_SENSOR_COMPASS (user_data);
	SignalContext *ctx = NULL;
	guint64 sensor_uid_low;
	guint64 sensor_uid_high;
	gfloat x;
	gfloat y;
	gfloat z;
	gfloat w;
	gfloat azimuth;

	g_object_get (sensor,
		      SSC_SENSOR_UID_HIGH, &sensor_uid_high,
		      SSC_SENSOR_UID_LOW, &sensor_uid_low,
		      NULL);

	if (sensor_uid_high == uid_high && sensor_uid_low == uid_low && msg_id == SSC_MSG_REPORT_MEASUREMENT) {
		msg = ssc_rotationvector_response__unpack (NULL, buf->len, (const uint8_t *) buf->data);

		if (msg == NULL) {
			g_warning ("Failed to unpack rotationvector measurement message");
			return;
		}

		if (msg->n_rotation >= 4) {
			x = msg->rotation[0];
			y = msg->rotation[1];
			z = msg->rotation[2];
			w = msg->rotation[3];
			azimuth = calculate_azimuth (x, y, z, w);

			/* Emit signal in main context instead of thread's context */
			ctx = g_slice_new0 (SignalContext);
			ctx->sensor = sensor;
			ctx->azimuth = azimuth;
			g_idle_add_full (G_PRIORITY_DEFAULT_IDLE, emit_signal, ctx, (GDestroyNotify)signal_context_free);
		}

		ssc_rotationvector_response__free_unpacked (msg, NULL);
	}
}

/*****************************************************************************/

static void
compass_close_ready (SSCSensor *sensor, GAsyncResult *result, gpointer user_data)
{
	GTask *task = G_TASK (user_data);
	g_autoptr (GError) error = NULL;

	if (!SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->close_finish (sensor, result, &error)) {
		g_task_return_boolean (task, FALSE);
		g_object_unref (task);
		return;
	}

	g_task_return_boolean (task, TRUE);
	g_object_unref (task);
}

gboolean
ssc_sensor_compass_close_finish (SSCSensorCompass *self, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

void
ssc_sensor_compass_close (SSCSensorCompass *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	GTask *task = NULL;
	SSCClient *client = NULL;
	SSCSensorCompassPrivate *priv = NULL;

	g_assert (SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->close &&
		  SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->close_finish);

	task = g_task_new (self, cancellable, callback, user_data);
	priv = ssc_sensor_compass_get_instance_private (self);

	/* Stop listening for reports */
	g_object_get (SSC_SENSOR (self),
		      SSC_SENSOR_CLIENT, &client,
		      NULL);

	if (priv->report_id)
		g_signal_handler_disconnect (client, priv->report_id);

	/* Close sensor */
	SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->close (SSC_SENSOR (self), cancellable, (GAsyncReadyCallback)compass_close_ready, task);
}

gboolean
ssc_sensor_compass_close_sync (SSCSensorCompass *self, GCancellable *cancellable, GError **error)
{
	gboolean success = FALSE;
	SyncContext ctx;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_compass_close (self, cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	success = ssc_sensor_compass_close_finish (self, ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return success;
}

/*****************************************************************************/

static void
compass_open_ready (SSCSensor *sensor, GAsyncResult *result, gpointer user_data)
{
	GTask *task = G_TASK (user_data);
	g_autoptr (GError) error = NULL;

	if (!SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->open_finish (sensor, result, &error)) {
		g_task_return_boolean (task, FALSE);
		g_object_unref (task);
		return;
	}

	g_task_return_boolean (task, TRUE);
	g_object_unref (task);
}

gboolean
ssc_sensor_compass_open_finish (SSCSensorCompass *self, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

void
ssc_sensor_compass_open (SSCSensorCompass *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	SSCSensorCompassPrivate *priv = NULL;
	SSCClient *client = NULL;
	GTask *task = NULL;

	g_assert (SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->open &&
		  SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->open_finish);

	priv = ssc_sensor_compass_get_instance_private (SSC_SENSOR_COMPASS (self));

	task = g_task_new (self, cancellable, callback, user_data);

	/* Start listening for reports before opening sensor so we don't miss the first measurement */
	g_object_get (SSC_SENSOR (self),
		      SSC_SENSOR_CLIENT, &client,
		      NULL);
	priv->report_id = g_signal_connect (client,
			"report",
			G_CALLBACK (report_received),
			self);

	/* Open sensor */
	SSC_SENSOR_CLASS (ssc_sensor_compass_parent_class)->open (SSC_SENSOR (self), cancellable, (GAsyncReadyCallback)compass_open_ready, task);
}

gboolean
ssc_sensor_compass_open_sync (SSCSensorCompass *self, GCancellable *cancellable, GError **error)
{
	SyncContext ctx;
	gboolean success = FALSE;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_compass_open (self, cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	success = ssc_sensor_compass_open_finish (self, ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return success;
}

/*****************************************************************************/

static void
ssc_sensor_compass_class_init (SSCSensorCompassClass *klass)
{
	signals[SIGNAL_MEASUREMENT] = g_signal_new ("measurement",
		G_TYPE_FROM_CLASS (klass),
		G_SIGNAL_RUN_FIRST,
		0, NULL, NULL, NULL,
		G_TYPE_NONE,
		3, G_TYPE_FLOAT, G_TYPE_FLOAT, G_TYPE_FLOAT);
}

static void
ssc_sensor_compass_init (SSCSensorCompass *self)
{
}

SSCSensorCompass *
ssc_sensor_compass_new_finish (GAsyncResult *result, GError **error)
{
	GObject *sensor;
	GObject *source;

	source = g_async_result_get_source_object (result);
	sensor = g_async_initable_new_finish (G_ASYNC_INITABLE (source), result, error);

	if (!sensor) {
		g_object_unref (source);
		return NULL;
	}

	g_object_unref (source);
	return SSC_SENSOR_COMPASS (sensor);
}

void
ssc_sensor_compass_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	g_async_initable_new_async (
			SSC_TYPE_SENSOR_COMPASS,
			G_PRIORITY_DEFAULT,
			cancellable,
			callback,
			user_data,
			SSC_SENSOR_DATA_TYPE, "rotv",
			NULL);
}

SSCSensorCompass *
ssc_sensor_compass_new_sync (GCancellable *cancellable, GError **error)
{
	SSCSensorCompass *self = NULL;
	SyncContext ctx;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_compass_new (cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	self = ssc_sensor_compass_new_finish (ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return self;
}
