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

#include "libssc-client-private.h"
#include "libssc-common-private.h"
#include "ssc-common.pb-c.h"
#include "ssc-sensor-light.pb-c.h"
#include "libssc-sensor-light.h"

enum {
	SIGNAL_MEASUREMENT,
	N_SIGNALS
};
static guint signals[N_SIGNALS];

typedef struct _SSCSensorLightPrivate {
	guint report_id;
} SSCSensorLightPrivate;

G_DEFINE_TYPE_WITH_CODE (SSCSensorLight, ssc_sensor_light, SSC_TYPE_SENSOR,
			 G_ADD_PRIVATE (SSCSensorLight))

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
	SSCSensorLight *sensor;
	gfloat intensity;
} SignalContext;

static void
signal_context_free (SignalContext *ctx)
{
	g_slice_free (SignalContext, ctx);
}

/*****************************************************************************/

static gboolean
emit_signal (gpointer user_data) {
	SignalContext *ctx = user_data;

	g_signal_emit (ctx->sensor, signals[SIGNAL_MEASUREMENT], 0, ctx->intensity);

	return G_SOURCE_REMOVE;
}

static void
report_received (SSCClient *self, guint32 msg_id, guint64 uid_high, guint64 uid_low, GArray *buf, gpointer user_data)
{
	SscLightResponse *msg = NULL;
	SSCSensorLight *sensor = SSC_SENSOR_LIGHT (user_data);
	SignalContext *ctx = NULL;
	guint64 sensor_uid_low;
	guint64 sensor_uid_high;
	gfloat intensity;

	g_object_get (sensor,
		      SSC_SENSOR_UID_HIGH, &sensor_uid_high,
		      SSC_SENSOR_UID_LOW, &sensor_uid_low,
		      NULL);

	if (sensor_uid_high == uid_high && sensor_uid_low == uid_low && msg_id == SSC_MSG_REPORT_MEASUREMENT) {
		msg = ssc_light_response__unpack (NULL, buf->len, (const uint8_t *) buf->data);

		if (msg == NULL) {
			g_warning ("Failed to unpack light measurement message");
			return;
		}

		/* Only report intensity in Lux, raw sensor values are ignored */
		if (msg->n_intensity >= 1) {
			intensity = msg->intensity[0];

			/* Emit signal in main context instead of thread's context if intensity is positive */
			if (intensity >= 0.0) {
				ctx = g_slice_new0 (SignalContext);
				ctx->sensor = sensor;
				ctx->intensity = intensity;
				g_idle_add_full (G_PRIORITY_DEFAULT_IDLE, emit_signal, ctx, (GDestroyNotify)signal_context_free);
			}
		}

		ssc_light_response__free_unpacked (msg, NULL);
	}
}

/*****************************************************************************/

static void
light_close_ready (SSCSensor *sensor, GAsyncResult *result, gpointer user_data)
{
	GTask *task = G_TASK (user_data);
	g_autoptr (GError) error = NULL;

	if (!SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->close_finish (sensor, result, &error)) {
		g_task_return_boolean (task, FALSE);
		g_object_unref (task);
		return;
	}

	g_task_return_boolean (task, TRUE);
	g_object_unref (task);
}

gboolean
ssc_sensor_light_close_finish (SSCSensorLight *self, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

void
ssc_sensor_light_close (SSCSensorLight *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	GTask *task = NULL;
	SSCClient *client = NULL;
	SSCSensorLightPrivate *priv = NULL;

	g_assert (SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->close &&
		  SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->close_finish);

	task = g_task_new (self, cancellable, callback, user_data);
	priv = ssc_sensor_light_get_instance_private (self);

	/* Stop listening for reports */
	g_object_get (SSC_SENSOR (self),
		      SSC_SENSOR_CLIENT, &client,
		      NULL);

	if (priv->report_id)
		g_signal_handler_disconnect (client, priv->report_id);

	/* Close sensor */
	SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->close (SSC_SENSOR (self), cancellable, (GAsyncReadyCallback)light_close_ready, task);
}

gboolean
ssc_sensor_light_close_sync (SSCSensorLight *self, GCancellable *cancellable, GError **error)
{
	gboolean success = FALSE;
	SyncContext ctx;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_light_close (self, cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	success = ssc_sensor_light_close_finish (self, ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return success;
}

/*****************************************************************************/

static void
light_open_ready (SSCSensor *sensor, GAsyncResult *result, gpointer user_data)
{
	GTask *task = G_TASK (user_data);
	g_autoptr (GError) error = NULL;


	if (!SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->open_finish (sensor, result, &error)) {
		g_task_return_boolean (task, FALSE);
		g_object_unref (task);
		return;
	}

	g_task_return_boolean (task, TRUE);
	g_object_unref (task);
}

gboolean
ssc_sensor_light_open_finish (SSCSensorLight *self, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

void
ssc_sensor_light_open (SSCSensorLight *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	SSCSensorLightPrivate *priv = NULL;
	SSCClient *client = NULL;
	GTask *task = NULL;

	g_assert (SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->open &&
		  SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->open_finish);

	priv = ssc_sensor_light_get_instance_private (SSC_SENSOR_LIGHT (self));

	task = g_task_new (self, cancellable, callback, user_data);

	/* Start listening for reports */
	g_object_get (SSC_SENSOR (self),
		      SSC_SENSOR_CLIENT, &client,
		      NULL);
	priv->report_id = g_signal_connect (client,
					    "report",
					    G_CALLBACK (report_received),
					    self);

	/* Open sensor */
	SSC_SENSOR_CLASS (ssc_sensor_light_parent_class)->open (SSC_SENSOR (self), cancellable, (GAsyncReadyCallback)light_open_ready, task);
}

gboolean
ssc_sensor_light_open_sync (SSCSensorLight *self, GCancellable *cancellable, GError **error)
{
	SyncContext ctx;
	gboolean success = FALSE;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_light_open (self, cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	success = ssc_sensor_light_open_finish (self, ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return success;
}

/*****************************************************************************/

static void
ssc_sensor_light_class_init (SSCSensorLightClass *klass)
{
	signals[SIGNAL_MEASUREMENT] = g_signal_new ("measurement",
		G_TYPE_FROM_CLASS (klass),
		G_SIGNAL_RUN_FIRST,
		0, NULL, NULL, NULL,
		G_TYPE_NONE,
		1, G_TYPE_FLOAT);
}

static void
ssc_sensor_light_init (SSCSensorLight *self)
{
}

SSCSensorLight *
ssc_sensor_light_new_finish (GAsyncResult *result, GError **error)
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
	return SSC_SENSOR_LIGHT (sensor);
}

void
ssc_sensor_light_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	g_async_initable_new_async (
			SSC_TYPE_SENSOR_LIGHT,
			G_PRIORITY_DEFAULT,
			cancellable,
			callback,
			user_data,
			SSC_SENSOR_DATA_TYPE, "ambient_light",
			NULL);
}

SSCSensorLight *
ssc_sensor_light_new_sync (GCancellable *cancellable, GError **error)
{
	SSCSensorLight *self = NULL;
	SyncContext ctx;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_light_new (cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	self = ssc_sensor_light_new_finish (ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return self;
}
