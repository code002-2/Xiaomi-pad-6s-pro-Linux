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

#include "libssc-client-private.h"

enum {
	SIGNAL_REPORT,
	SIGNAL_SENSOR_INITIALIZED,
	N_SIGNALS
};
static guint signals[N_SIGNALS];

enum {
	PROP_FILE = 1,
	N_PROPERTIES
};

typedef struct _SSCClientPrivate {
	QmiDevice *device;
	QmiClientSsc *qmi_client_ssc;
	QrtrBus *bus;
	guint32 node_id;
	guint indication_report_small_id;
	guint indication_report_large_id;
	guint sensor_initialized_id;
	guint discovery_requests;
	guint sensor_init_requests;
} SSCClientPrivate;

typedef struct _SSCClient {
	GObject parent;
	SSCClientPrivate *priv;
} SSCClient;

GQuark ssc_client_error_quark (void)
{
  static GQuark quark = 0;

  if (!quark)
    quark = g_quark_from_static_string("ssc-client");

  return quark;
}


static void async_initable_iface_init (GAsyncInitableIface *iface);

G_DEFINE_TYPE_WITH_CODE (SSCClient, ssc_client, G_TYPE_OBJECT,
			 G_ADD_PRIVATE (SSCClient)
			 G_IMPLEMENT_INTERFACE (G_TYPE_ASYNC_INITABLE, async_initable_iface_init));

typedef struct {
	GMainLoop *loop;
	GAsyncResult *result;
	GObject *object;
} SyncContext;

static void
sync_cb (GObject *source, GAsyncResult *result, gpointer user_data)
{
	SyncContext *ctx = user_data;

	ctx->result = g_object_ref (result);
	g_main_loop_quit (ctx->loop);
}

/*****************************************************************************/

static void
handle_report (SSCClient *self, GArray *protobuf)
{
	SscClientResponse *msg;

	msg = ssc_client_response__unpack (NULL, protobuf->len, (const uint8_t *) protobuf->data);
	if (msg == NULL)
	{
		g_warning ("Failed to unpack message");
		return;
	}

	for (gsize i = 0; i < msg->n_response; i++) {
		SscClientResponseBody *body = msg->response[i];
		GArray* buf = g_array_new (FALSE, FALSE, 1);
		g_array_set_size (buf, body->msg.len);
		memcpy (buf->data, (char *) body->msg.data, body->msg.len);

		g_debug ("Message %" G_GUINT32_FORMAT " for sensor %016lX %016lX", body->msg_id, msg->uid->high, msg->uid->low);

		/*
		 * Emit a GSignal on which sensor drivers can subscribe to
		 * receive sensor specific messages. Drivers can emit the sensor data
		 * once they have processed it.
		 */
		g_signal_emit (self, signals[SIGNAL_REPORT], 0, body->msg_id, msg->uid->high, msg->uid->low, buf);
		g_array_free (buf, TRUE);
	}

	ssc_client_response__free_unpacked (msg, NULL);
}

static void
report_large_received (QmiClientSsc *self, QmiIndicationSscReportLargeOutput *output, gpointer user_data)
{
	SSCClient *client = SSC_CLIENT (user_data);
	g_autoptr (GError) error = NULL;
	GArray *protobuf = NULL;

	if (!qmi_indication_ssc_report_large_output_get_data (output, &protobuf, &error)) {
		g_warning ("Cannot extract Protobuf data (large report): %s", error->message);
		return;
	}

	handle_report (client, protobuf);
}

static void
report_small_received (QmiClientSsc *self, QmiIndicationSscReportSmallOutput *output, gpointer user_data)
{
	SSCClient *client = SSC_CLIENT (user_data);
	g_autoptr (GError) error = NULL;
	GArray *protobuf = NULL;

	if (!qmi_indication_ssc_report_small_output_get_data (output, &protobuf, &error)) {
		g_warning ("Cannot extract Protobuf data (small report): %s", error->message);
		return;
	}

	handle_report (client, protobuf);
}

static void
request_ready (QmiClientSsc *self, GAsyncResult *res, gpointer user_data)
{
	GError *error = NULL;
	GTask *task = G_TASK (user_data);
	QmiMessageSscControlOutput *output = NULL;

	output = qmi_client_ssc_control_finish (self, res, &error);
	if (!output) {
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	if (!qmi_message_ssc_control_output_get_result (output, &error)) {
		g_warning ("QMI request failed: %s", error->message);
		qmi_message_ssc_control_output_unref (output);
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	qmi_message_ssc_control_output_unref (output);
	g_task_return_boolean (task, TRUE);
	g_clear_object (&task);
}

gboolean
ssc_client_send_finish (SSCClient *self, GAsyncResult *res, GError **error)
{
	return g_task_propagate_boolean (G_TASK (res), error);
}

void
ssc_client_send (SSCClient *self, guint64 uid_high, guint64 uid_low, guint32 message_id, GArray *protobuf, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	GTask *task = NULL;
	GError *error = NULL;
	QmiMessageSscControlInput *input = NULL;
	SSCClientPrivate *priv = NULL;
	g_autoptr (GArray) buf = NULL;
	SscClientRequestBody body_msg;
	SscClientConfig config_msg;
	SscClientRequest client_msg;
	SscUid uid_msg;

	task = g_task_new (self, cancellable, callback, user_data);
	buf = g_array_new (FALSE, FALSE, 1);
	priv = ssc_client_get_instance_private (self);

	ssc_client_config__init (&config_msg);
	config_msg.processor = SSC_PROCESSOR_APSS;
	config_msg.suspend_mode = SSC_SUSPEND_MODE_WAKEUP;

	ssc_client_request_body__init (&body_msg);
	if (protobuf) {
		body_msg.has_msg = true;
		body_msg.msg.data = (uint8_t *)protobuf->data;
		body_msg.msg.len = protobuf->len;
	}

	ssc_uid__init (&uid_msg);
	uid_msg.low = uid_low;
	uid_msg.high = uid_high;

	ssc_client_request__init (&client_msg);
	client_msg.uid = &uid_msg;
	client_msg.msg_id = message_id;
	client_msg.config = &config_msg;
	client_msg.request = &body_msg;

	g_array_set_size (buf, ssc_client_request__get_packed_size (&client_msg));
	ssc_client_request__pack (&client_msg, (unsigned char*) buf->data);

	if (buf == NULL) {
		g_set_error (&error, ssc_client_error_quark(), SSC_CLIENT_ERROR_PROTOBUF,
			     "Protobuf message couldn't be build for SUID sensor");
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	/* Build QMI message */
	input = qmi_message_ssc_control_input_new ();

	if (!qmi_message_ssc_control_input_set_report_type (input, QMI_SSC_REPORT_TYPE_LARGE, &error)) {
		g_debug ("Inserting report type failed: %s", error->message);
		qmi_message_ssc_control_input_unref (input);
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	if (!qmi_message_ssc_control_input_set_data (input, buf, &error)) {
		g_debug ("Inserting protobuf data failed: %s", error->message);
		qmi_message_ssc_control_input_unref (input);
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	/* Send QMI message with Protobuf payload */
	qmi_client_ssc_control (priv->qmi_client_ssc,
		input,
		10,
		g_task_get_cancellable (task),
		(GAsyncReadyCallback)request_ready,
		task);

	qmi_message_ssc_control_input_unref (input);
}

/*****************************************************************************/

static void
allocate_client_ready (QmiDevice *device, GAsyncResult *result, gpointer user_data)
{
	GError *error = NULL;
	GTask *task = NULL;
	SSCClient *client = NULL;
	SSCClientPrivate *priv = NULL;

	task = G_TASK (user_data);
	client = g_task_get_task_data (task);
	priv = ssc_client_get_instance_private (client);

	priv->qmi_client_ssc = QMI_CLIENT_SSC (qmi_device_allocate_client_finish (device, result, &error));

	if (error) {
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	/* Connecting signals for QMI indication with Protobuf response */
	g_debug ("Connecting QMI SSC client signals");
	priv->indication_report_small_id = g_signal_connect (priv->qmi_client_ssc,
			"report-small",
			G_CALLBACK (report_small_received),
			client);
	priv->indication_report_large_id = g_signal_connect (priv->qmi_client_ssc,
			"report-large",
			G_CALLBACK (report_large_received),
			client);

	g_task_return_boolean (task, TRUE);
	g_clear_object (&task);
}

static void
device_open_ready (QmiDevice *device, GAsyncResult *result, gpointer user_data)
{
	GError *error = NULL;
	GTask *task = NULL;

	task = G_TASK (user_data);

	qmi_device_open_finish (device, result, &error);
	if (error) {
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	g_debug ("QMI device at '%s' ready", qmi_device_get_path_display (device));

	/* QMI device opened, allocate client */
	qmi_device_allocate_client (device,
		QMI_SERVICE_SSC,
		QMI_CID_NONE,
		10,
		g_task_get_cancellable (task),
		(GAsyncReadyCallback)allocate_client_ready,
		task);
}

static void
device_new_ready (GObject *source, GAsyncResult *res, gpointer user_data)
{
	QmiDeviceOpenFlags open_flags = QMI_DEVICE_OPEN_FLAGS_NONE;
	GError *error = NULL;
	GTask *task = NULL;
	SSCClient *client = NULL;
	SSCClientPrivate *priv = NULL;

	task = G_TASK (user_data);
	client = g_task_get_task_data (task);
	priv = ssc_client_get_instance_private (client);

	priv->device = qmi_device_new_finish (res, &error);
	if (error) {
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	/* Indications are expected as they report all sensor data values */
	open_flags |= QMI_DEVICE_OPEN_FLAGS_AUTO;
	open_flags |= QMI_DEVICE_OPEN_FLAGS_EXPECT_INDICATIONS;
	
	g_debug ("QMI device ready");

	/* QMI device created, open device */
	qmi_device_open (priv->device,
		open_flags,
		15,
		g_task_get_cancellable (task),
		(GAsyncReadyCallback)device_open_ready,
		task);
}

static void
bus_new_ready (GObject *source, GAsyncResult *res, gpointer user_data)
{
	GError *error = NULL;
	QrtrNode *node = NULL;
	GTask *task = NULL;
	SSCClient *client = NULL;
	SSCClientPrivate *priv = NULL;
	gboolean found = FALSE;

	task = G_TASK (user_data);
	client = g_task_get_task_data (task);
	priv = ssc_client_get_instance_private (client);

	priv->bus = qrtr_bus_new_finish (res, &error);
	if (error) {
		g_warning ("QRTR bus unavailable. Make sure access to AF_QIPCRTR address family is granted.");
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	/* Find QRTR node for SSC service */
	for (GList *l = qrtr_bus_peek_nodes (priv->bus); l != NULL; l = l->next) {
		node = l->data;

		if (node && qrtr_node_lookup_port (node, QMI_SERVICE_SSC) >= 0) {
			found = TRUE;
			break;
		}
	}

	if (!found) {
		g_debug ("Service SSC not found");
		g_set_error (&error, ssc_client_error_quark(), SSC_CLIENT_ERROR_LOOKUP,
			     "SSC QMI Service not found");
		g_task_return_error (task, error);
		g_clear_object (&task);
		return;
	}

	g_debug("QRTR node discovered for SSC service");

	/* QRTR node ready, create QMI device */
	qmi_device_new_from_node (node,
		g_task_get_cancellable (task),
		(GAsyncReadyCallback)device_new_ready,
		task);
}


static void
ssc_client_init (SSCClient *self)
{
}

static void
ssc_client_dispose (GObject *object)
{
	QmiDeviceReleaseClientFlags flags = QMI_DEVICE_RELEASE_CLIENT_FLAGS_NONE;
	SSCClientPrivate *priv = NULL;
	GMainContext *context = NULL;
	GError *error = NULL;
	SyncContext ctx;

	priv = ssc_client_get_instance_private (SSC_CLIENT (object));

	if (!priv->qmi_client_ssc) {
		g_debug ("No SSC QMI client to release.");
		return;
	}

	/* Sync context */
	context = g_main_context_new ();
	g_main_context_push_thread_default (context);
	ctx.loop = g_main_loop_new (context, TRUE);
	ctx.object = object;

	/* Release QMI client */
	g_debug ("Releasing SSC QMI client");
	g_assert_nonnull (priv->qmi_client_ssc);
	flags |= QMI_DEVICE_RELEASE_CLIENT_FLAGS_RELEASE_CID;

	qmi_device_release_client (priv->device,
				   QMI_CLIENT (priv->qmi_client_ssc),
				   flags,
				   10,
				   NULL,
				   sync_cb,
				   &ctx);
	g_main_loop_run (ctx.loop);

	/* QMI client released, check result */
	if (!qmi_device_release_client_finish (priv->device, ctx.result, &error))
		g_warning ("Could not release SSC QMI client: %s\n", error->message);

	g_clear_object (&priv->qmi_client_ssc);
	g_clear_object (&priv->device);
	G_OBJECT_CLASS (ssc_client_parent_class)->dispose (object);

	/* Close context */
	g_main_context_pop_thread_default (context);
	g_main_loop_unref (ctx.loop);
	g_object_unref (ctx.result);
}

static void
initable_init_async (GAsyncInitable *initable, int io_priority, GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
#if QMI_QRTR_SUPPORTED
	{
		GTask *task = NULL;
		SSCClient *self = NULL;
		g_autofree gchar *id = NULL;

		self = SSC_CLIENT (initable);

		task = g_task_new (self, cancellable, callback, user_data);
		g_task_set_task_data (task, self, NULL);

		/* Open right node on QRTR bus */
		qrtr_bus_new (1000, /* ms */
			      NULL,
			      (GAsyncReadyCallback)bus_new_ready,
			      task);
		return;
	}
# else
	g_debug ("Only QRTR QMI devices are supported. Compile libqmi with QRTR support");
	g_task_return_boolean (task, FALSE);
	g_clear_object (&task);
	return;
#endif
}

static gboolean
initable_init_finish (GAsyncInitable *initable, GAsyncResult *result, GError **error)
{
	return g_task_propagate_boolean (G_TASK (result), error);
}

static void
async_initable_iface_init (GAsyncInitableIface *iface)
{
	iface->init_async = initable_init_async;
	iface->init_finish = initable_init_finish;
}

static void
ssc_client_class_init (SSCClientClass *klass)
{
	GObjectClass *object_class = G_OBJECT_CLASS (klass);

	/* Virtual methods */
	object_class->dispose = ssc_client_dispose;

	/* Signals */
	signals[SIGNAL_REPORT] = g_signal_new ("report",
		G_TYPE_FROM_CLASS (klass),
		G_SIGNAL_RUN_FIRST,
		0, NULL, NULL, NULL,
		G_TYPE_NONE,
		4, G_TYPE_UINT, G_TYPE_UINT64, G_TYPE_UINT64, G_TYPE_ARRAY);
	signals[SIGNAL_SENSOR_INITIALIZED] = g_signal_new ("sensor-initialized",
		G_TYPE_FROM_CLASS (klass),
		G_SIGNAL_RUN_FIRST,
		0, NULL, NULL, NULL,
		G_TYPE_NONE,
		1, SSC_TYPE_SENSOR);
}

SSCClient *
ssc_client_new_finish (GAsyncResult *result, GError **error)
{
	GObject *client;
	GObject *source;

	source = g_async_result_get_source_object (result);
	client = g_async_initable_new_finish (G_ASYNC_INITABLE (source), result, error);
	g_object_unref (source);

	if (!client)
		return NULL;

	return SSC_CLIENT (client);
}

void
ssc_client_new (GCancellable *cancellable, GAsyncReadyCallback callback, gpointer user_data)
{
	g_async_initable_new_async (
		SSC_TYPE_CLIENT,
		G_PRIORITY_DEFAULT,
		cancellable,
		callback,
		user_data,
		NULL);
}
