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

#include "ssc-common.pb-c.h"
#include "ssc-sensor-proximity.pb-c.h"
#include "libssc-client-private.h"
#include "libssc-common-private.h"
#include "libssc-sensor-proximity.h"

#define SSC_SENSOR_PROXIMITY_NEAR	1
#define SSC_SENSOR_PROXIMITY_FAR	0

enum {
	SIGNAL_MEASUREMENT,
	N_SIGNALS
};
static guint signals[N_SIGNALS];

typedef struct _SSCSensorProximityPrivate {
	guint report_id;
	gboolean near;
	gboolean reported_once;
} SSCSensorProximityPrivate;

G_DEFINE_TYPE_WITH_CODE (SSCSensorProximity, ssc_sensor_proximity, SSC_TYPE_SENSOR,
			 G_ADD_PRIVATE (SSCSensorProximity))

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
	SSCSensorProximity *sensor;
	gboolean near;
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

	g_signal_emit (ctx->sensor, signals[SIGNAL_MEASUREMENT], 0, ctx->near);

	return G_SOURCE_REMOVE;
}

static void
report_received (SSCClient *self, guint32 msg_id, guint64 uid_high, guint64 uid_low, GArray *buf, gpointer user_data)
{
	SSCSensorProximity *sensor = SSC_SENSOR_PROXIMITY (user_data);
	SSCSensorProximityPrivate *priv = NULL;
	SignalContext *ctx = NULL;
	guint64 sensor_uid_low;
	guint64 sensor_uid_high;
	gboolean near = false;

	g_object_get (SSC_SENSOR (sensor),
		      SSC_SENSOR_UID_HIGH, &sensor_uid_high,
		      SSC_SENSOR_UID_LOW, &sensor_uid_low,
		      NULL);

	if (sensor_uid_high == uid_high && sensor_uid_low == uid_low) {
		/* Most devices use REPORT_MEASUREMENT_PROXIMITY */
		if (msg_id == SSC_MSG_REPORT_MEASUREMENT_PROXIMITY) {
			SscProximityResponse *msg = ssc_proximity_response__unpack (NULL, buf->len, (const uint8_t *) buf->data);
			if (msg == NULL) {
				g_warning ("Failed to unpack proximity measurement message");
				return;
			}

			switch (msg->near) {
				case SSC_SENSOR_PROXIMITY_NEAR:
					near = true;
					break;
				case SSC_SENSOR_PROXIMITY_FAR:
					near = false;
					break;
				default:
					g_assert_not_reached ();
			}

			ssc_proximity_response__free_unpacked (msg, NULL);
		/* xiaomi-davinci uses REPORT_MEASUREMENT and its own proximity response */
		} else if (msg_id == SSC_MSG_REPORT_MEASUREMENT) {
			ProximityDataDavinci data;
			SscProximityResponseDavinci *msg = ssc_proximity_response_davinci__unpack (NULL, buf->len, (const uint8_t *) buf->data);

			if (msg == NULL) {
				g_warning ("Failed to unpack Xiaomi Davinci proximity measurement message");
				return;
			}

			if (msg->data->len != sizeof(ProximityDataDavinci)) {
				/* Not observed and unlikely to ever happen due to reserved fields in the data struct */
				ssc_proximity_response_davinci__free_unpacked (msg, NULL);
				return;
			}

			memcpy(&data, msg->data->data, sizeof(ProximityDataDavinci));

			switch ((int)data.near) {
				case SSC_SENSOR_PROXIMITY_NEAR:
					near = true;
					break;
				case SSC_SENSOR_PROXIMITY_FAR:
					near = false;
					break;
				default:
					g_assert_not_reached ();
			}

			ssc_proximity_response_davinci__free_unpacked (msg, NULL);
		} else {
			return;
		}

		/* Only emit signal when measurement actually changed or if the sensor was recently opened */
		priv = ssc_sensor_proximity_get_instance_private (sensor);
		if (priv->near != near || !priv->reported_once) {
			priv->near = near;
			priv->reported_once = TRUE;

			/* Emit signal in main context instead of thread's context */
			ctx = g_slice_new0 (SignalContext);
			ctx->sensor = sensor;
			ctx->near = near;
			g_idle_add_full (G_PRIORITY_DEFAULT_IDLE, emit_signal, ctx, (GDestroyNotify)signal_context_free);
		}
	}
}

/*****************************************************************************/

static void
proximity_close_ready (SSCSensor *sensor, GAsyncResult *result, gpointer user_data)
{
	GTask *task = G_TASK (user_data);
	g_autoptr (GError) error = NULL;

	if (!SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->close_finish (sensor, result, &error)) {
		g_task_return_boolean (task, FALSE);
		g_object_unref (task);
		return;
	}

	g_task_return_boolean (task, TRUE);
	g_object_unref (task);
}

gboolean
ssc_sensor_proximity_close_finish (SSCSensorProximity *self, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

void
ssc_sensor_proximity_close (SSCSensorProximity *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	GTask *task = NULL;
	SSCClient *client = NULL;
	SSCSensorProximityPrivate *priv = NULL;

	g_assert (SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->close &&
		  SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->close_finish);

	task = g_task_new (self, cancellable, callback, user_data);
	priv = ssc_sensor_proximity_get_instance_private (self);

	/* Stop listening for reports */
	g_object_get (SSC_SENSOR (self),
		      SSC_SENSOR_CLIENT, &client,
		      NULL);
	if (priv->report_id)
		g_signal_handler_disconnect (client, priv->report_id);

	/* Close sensor */
	SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->close (SSC_SENSOR (self), cancellable, (GAsyncReadyCallback)proximity_close_ready, task);
}

gboolean
ssc_sensor_proximity_close_sync (SSCSensorProximity *self, GCancellable *cancellable, GError **error)
{
	gboolean success = FALSE;
	SyncContext ctx;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_proximity_close (self, cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	success = ssc_sensor_proximity_close_finish (self, ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return success;
}

/*****************************************************************************/

static void
proximity_open_ready (SSCSensor *sensor, GAsyncResult *result, gpointer user_data)
{
	GTask *task = G_TASK (user_data);
	g_autoptr (GError) error = NULL;

	if (!SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->open_finish (sensor, result, &error)) {
		g_task_return_boolean (task, FALSE);
		g_object_unref (task);
		return;
	}

	g_task_return_boolean (task, TRUE);
	g_object_unref (task);
}

gboolean
ssc_sensor_proximity_open_finish (SSCSensorProximity *self, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

void
ssc_sensor_proximity_open (SSCSensorProximity *self, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	SSCClient *client = NULL;
	SSCSensorProximityPrivate *priv = NULL;
	GTask *task = NULL;

	g_assert (SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->open &&
		  SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->open_finish);

	priv = ssc_sensor_proximity_get_instance_private (self);
	priv->reported_once = FALSE;

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
	SSC_SENSOR_CLASS (ssc_sensor_proximity_parent_class)->open (SSC_SENSOR (self), cancellable, (GAsyncReadyCallback)proximity_open_ready, task);
}

gboolean
ssc_sensor_proximity_open_sync (SSCSensorProximity *self, GCancellable *cancellable, GError **error)
{
	SyncContext ctx;
	gboolean success = FALSE;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	ssc_sensor_proximity_open (self, cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	success = ssc_sensor_proximity_open_finish (self, ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return success;
}

/*****************************************************************************/

static void
ssc_sensor_proximity_class_init (SSCSensorProximityClass *klass)
{
	signals[SIGNAL_MEASUREMENT] = g_signal_new ("measurement",
		G_TYPE_FROM_CLASS (klass),
		G_SIGNAL_RUN_FIRST,
		0, NULL, NULL, NULL,
		G_TYPE_NONE,
		1, G_TYPE_BOOLEAN);
}

static void
ssc_sensor_proximity_init (SSCSensorProximity *self)
{
}

SSCSensorProximity *
ssc_sensor_proximity_new_finish (GAsyncResult *result, GError **error)
{
	GObject *sensor;
	GObject *source;
	SSCSensorProximityPrivate *priv = NULL;

	source = g_async_result_get_source_object (result);
	sensor = g_async_initable_new_finish (G_ASYNC_INITABLE (source), result, error);

	if (!sensor) {
		g_object_unref (source);
		return NULL;
	}

	priv = ssc_sensor_proximity_get_instance_private (SSC_SENSOR_PROXIMITY (sensor));

	/* Only bypass reporting once if the sensor is opened, not during initialization */
	priv->reported_once = TRUE;

	g_object_unref (source);
	return SSC_SENSOR_PROXIMITY (sensor);
}

void
ssc_sensor_proximity_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	g_async_initable_new_async (
			SSC_TYPE_SENSOR_PROXIMITY,
			G_PRIORITY_DEFAULT,
			cancellable,
			callback,
			user_data,
			SSC_SENSOR_DATA_TYPE, "proximity",
			NULL);
}

SSCSensorProximity *
ssc_sensor_proximity_new_sync (GCancellable *cancellable, GError **error)
{
	SSCSensorProximity *self = NULL;
	SyncContext ctx;

	ctx.loop = g_main_loop_new (NULL, FALSE);

	/* Create sensor */
	ssc_sensor_proximity_new (cancellable, sync_cb, &ctx);
	g_main_loop_run (ctx.loop);
	self = ssc_sensor_proximity_new_finish (ctx.result, error);

	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);

	return self;
}
