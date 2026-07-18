#!/usr/bin/env python3
#
# libssc: Library to expose Qualcomm Sensor Core sensors
# Copyright (C) 2022-2025 Dylan Van Assche
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
import sys
import time
import json
import random
from enum import Enum
from typing import Tuple
from glob import glob
from qmi import QMI, ValueType, MessageType
import ssc_sensor_suid_pb2 as SensorSuid
import ssc_common_pb2 as SscCommon
import ssc_sensor_proximity_pb2 as SensorProximity
import ssc_sensor_accelerometer_pb2 as SensorAccelerometer
import ssc_sensor_magnetometer_pb2 as SensorMagnetometer
import ssc_sensor_light_pb2 as SensorLight
import ssc_sensor_rotationvector_pb2 as SensorCompass

SSC_SERVICE_ID = 0x190
SSC_CLIENT_ID = 1

SSC_CONTROL_MSG_ID = 0x0020
SSC_CONTROL_MSG_SUCCESS_ID = 0x2
SSC_CONTROL_MSG_REPORT_TYPE_ID = 0x10
SSC_CONTROL_MSG_CLIENT_ID = 0x10
SSC_CONTROL_MSG_DATA_ID = 0x1

SSC_REPORT_SMALL_MSG_ID = 0x0021
SSC_REPORT_SMALL_CLIENT_ID = 0x01
SSC_REPORT_SMALL_DATA = 0x02
SSC_REPORT_LARGE_MSG_ID = 0x0022
SSC_REPORT_LARGE_CLIENT_ID = 0x01
SSC_REPORT_LARGE_DATA = 0x02

SSC_SUID_SENSOR_UID_HIGH = 0xABABABABABABABAB
SSC_SUID_SENSOR_UID_LOW = 0xABABABABABABABAB

SSC_PROTOBUF_DISCOVERY_MSG_ID = 768
SSC_PROTOBUF_DISCOVER_MSG_ID = 512
SSC_PROTOBUF_GET_ATTRIBUTE_MSG_ID = 1
SSC_PROTOBUF_RESPONSE_GET_ATTRIBUTES_MSG_ID = 128
SSC_PROTOBUF_ENABLE_REPORT_MSG_ID = 514
SSC_PROTOBUF_DISABLE_REPORT_MSG_ID = 10
SSC_PROTOBUF_ENABLE_CONTINUOUS_MSG_ID = 513


class ReportType(Enum):
    """
        SSC report type enum.
    """
    SMALL = 0x0
    LARGE = 0x1
    UNKNOWN = sys.maxsize


class DataType(Enum):
    """
        SSC sensor data types.
    """
    PROXIMITY = 'proximity'
    ACCELEROMETER = 'accel'
    MAGNETOMETER = 'mag'
    LIGHT = 'ambient_light'
    ROTATIONVECTOR = 'rotv'


class SSC():
    """
    Qualcomm's Snapdragon Sensor Core QMI messages.
    """

    @staticmethod
    def _read_data() -> dict:
        """
        Read JSON data with sensor configuration and fake measurements.

        Returns
        -------
        data : dict
            Sensor configuration and fake measurements.
        """
        data = []

        for sensor in glob('data/sensor-*.json'):
            with open(sensor) as f:
                data.append(json.load(f))

        return data

    @staticmethod
    def parse_message_control_input(message: bytes) -> Tuple[ReportType, bytes, int]:
        """
        Parse a raw QMI SSC Control Message Input from a client.

        Parameters
        ----------
        message : bytes
            Raw QMI message to parse.

        Returns
        -------
        report_type : ReportType
            Report type requested by client.
        data : bytes
            Protobuf data passed by client.
        transaction_id : int
            Transaction ID to use for replies.

        Raises
        ------
        NotImplementedError
            If the QMI report type is not supported.
        """
        # QMI header validation and transaction ID
        message_type, transaction_id, message_id, message_length = QMI.parse_header(message)
        assert message_type == MessageType.REQUEST
        assert message_id == SSC_CONTROL_MSG_ID

        # TLV report type
        tlv_type, tlv_length, tlv_value = QMI.parse_tlv(message,
                                                        SSC_CONTROL_MSG_REPORT_TYPE_ID,
                                                        ValueType.INT)
        if tlv_value == ReportType.SMALL.value:
            report_type = ReportType.SMALL
        elif tlv_value == ReportType.LARGE.value:
            report_type = ReportType.LARGE
        else:
            raise NotImplementedError(f'Unknown report type: {tlv_value}')

        # TLV data
        tlv_type, tlv_length, tlv_value = QMI.parse_tlv(message,
                                                        SSC_CONTROL_MSG_DATA_ID,
                                                        ValueType.ARRAY)
        data = tlv_value

        return report_type, data, transaction_id

    @staticmethod
    def parse_protobuf_client_request(message: bytes) -> Tuple[int, int, int]:
        """
        Parse a Protobuf client request to extract sensor UID.

        Parameters
        ----------
        message : bytes
            Protobuf message to parse.

        Returns
        -------
        message_id : int
            ID of the Protobuf message
        uid_high : int
            UID 64 bits high.
        uid_low : int
            UID 64 bits low.
        """

        client_request = SscCommon.SscClientRequest()
        client_request.ParseFromString(message)
        uid_high = client_request.uid.high
        uid_low = client_request.uid.low
        message_id = client_request.msg_id

        return message_id, uid_high, uid_low

    @staticmethod
    def parse_protobuf_discovery_request(message: bytes) -> str:
        """
        Parse a Protobuf discovery request to extract the sensor data type to discover.

        Parameters
        ----------
        message : bytes
            Protobuf message to parse.

        Returns
        -------
        data_type : str
            Sensor data type.
        """

        client_request = SscCommon.SscClientRequest()
        client_request.ParseFromString(message)

        suid_request = SensorSuid.SscSuidRequest()
        suid_request.ParseFromString(client_request.request.msg)
        data_type = suid_request.data_type

        return data_type


    @staticmethod
    def generate_message_control_output(transaction_id: int) -> bytes:
        """
        Generate a QMI SSC Control Message Output as a reply.

        Parameters
        ----------
        transaction_id : int
            QMI transaction ID to use for replies.

        Returns
        -------
        message : bytes
            Generated QMI message as raw bytes.
        """
        message = QMI.generate_header(MessageType.RESPONSE,
                                      transaction_id,
                                      SSC_CONTROL_MSG_ID)

        # QMI Success response
        value = bytes()
        value += int(0x000).to_bytes(2, byteorder='little')
        value += int(0x000).to_bytes(2, byteorder='little')
        message = QMI.generate_tlv(message, SSC_CONTROL_MSG_SUCCESS_ID, value, ValueType.SEQUENCE)

        # SSC Client ID: not used by libssc
        value = bytes()
        value += int(SSC_CLIENT_ID).to_bytes(4, byteorder='little')
        message = QMI.generate_tlv(message, SSC_CONTROL_MSG_CLIENT_ID, value, ValueType.INT)

        # SSC Response (TODO): not used by libssc

        return message

    @staticmethod
    def generate_protobuf_discovery_response(data_type: str) -> bytes:
        """
        Generates a Protobuf message to discovery a sensor for a given data type.

        Parameters
        ----------
        data_type : str
            Sensor to discover for data type.

        Returns
        -------
        protobuf : bytes
            Protobuf message in bytes.

        Raises
        ------
        NotImplementedError
            If no sensor implementation can be found for the data type.
        """
        # Extract sensor UID by data type
        data = SSC._read_data()
        uid_high = None
        uid_low = None
        supported = False

        for entry in data:
            sensor = entry['sensor']
            if sensor['data_type'] == data_type:
                uid_high = int(sensor['uid_high'], 16)
                uid_low = int(sensor['uid_low'], 16)
                supported = True
                break

        # Generate discovery response 
        suid_response = SensorSuid.SscSuidResponse()
        suid_response.data_type = data_type
        if supported and uid_high is not None and uid_low is not None:
            sensor_uid = SscCommon.SscUid()
            sensor_uid.high = uid_high
            sensor_uid.low = uid_low
            suid_response.uid.append(sensor_uid)

        # Protobuf envelope to pack discovery message
        client_response_body = SscCommon.SscClientResponseBody()
        client_response_body.msg = suid_response.SerializeToString()
        client_response_body.msg_id = SSC_PROTOBUF_DISCOVERY_MSG_ID
        client_response_body.timestamp = int(time.time())

        client_response = SscCommon.SscClientResponse()
        client_response.response.append(client_response_body)
        client_response.uid.high = SSC_SUID_SENSOR_UID_HIGH 
        client_response.uid.low = SSC_SUID_SENSOR_UID_LOW

        protobuf = client_response.SerializeToString()
        return protobuf

    @staticmethod
    def generate_protobuf_attributes_response(uid_high: int, uid_low: int) -> bytes:
        """
        Generate a Protobuf message with all attributes of a sensor.

        Parameters
        ----------
        uid_high : int
            UID 64 bits high.
        uid_low : int
            UID 64 bits low.

        Returns
        -------
        protobuf : bytes
            Protobuf message in bytes.

        Raises
        ------
        NotImplementedError
            If no attributes can be found for the sensor UID.
        """
        # Extract sensor attributes for requested sensor by UID
        data = SSC._read_data()
        attributes = []

        for entry in data:
            sensor = entry['sensor']
            if int(sensor['uid_high'], 16) == uid_high and int(sensor['uid_low'], 16) == uid_low:
                for a in entry['attributes']:
                    attr_id = entry['attributes'][a]['id']
                    attr_value = entry['attributes'][a]['value']
                    if type(attr_value) is int:
                        attributes.append((attr_id, SscCommon.SscAttrValue(i=attr_value)))
                    elif type(attr_value) is float:
                        attributes.append((attr_id, SscCommon.SscAttrValue(f=attr_value)))
                    elif type(attr_value) is str:
                        attributes.append((attr_id, SscCommon.SscAttrValue(s=attr_value)))
                    elif type(attr_value) is bool:
                        attributes.append((attr_id, SscCommon.SscAttrValue(b=attr_value)))
                    else:
                        raise NotImplementedError('Attribute value type unsupported')
                break

        if not attributes:
            raise NotImplementedError('Unable to match sensor {uid_high},{uid_low} with attributes')

        # Generate attributes response 
        attr_response = SscCommon.SscAttrResponse()
        for a in attributes:
            attr = SscCommon.SscAttr()
            attr_array_value = SscCommon.SscAttrArrayValue()
            attr.id = a[0]
            attr.value_array.v.append(a[1])
            attr_response.attr.append(attr)

        # Protobuf envelope to pack attributes message
        client_response_body = SscCommon.SscClientResponseBody()
        client_response_body.msg = attr_response.SerializeToString()
        client_response_body.msg_id = SSC_PROTOBUF_RESPONSE_GET_ATTRIBUTES_MSG_ID
        client_response_body.timestamp = int(time.time())

        client_response = SscCommon.SscClientResponse()
        client_response.response.append(client_response_body)
        client_response.uid.high = uid_high 
        client_response.uid.low = uid_low

        protobuf = client_response.SerializeToString()
        return protobuf

    @staticmethod
    def generate_protobuf_sensor_measurement(uid_high: int, uid_low: int, index: int) -> bytes:
        """
        Instantiates a Protobuf sensor measurement message.

        Parameters
        ----------
        uid_high : int
            UID 64 bits high.
        uid_low : int
            UID 64 bits low.

        Returns
        -------
        protobuf : bytes
            Protobuf message in bytes.

        Raises
        ------
        NotImplementedError
            If no sensor measurements can be found for the sensor UID.
        """
        # Extract sensor measurements for requested sensor by UID
        data = SSC._read_data()
        data_type = ''
        measurements = []

        for entry in data:
            sensor = entry['sensor']
            data_type = sensor['data_type']
            if int(sensor['uid_high'], 16) == uid_high and int(sensor['uid_low'], 16) == uid_low:
                while len(entry['measurements']) <= index:
                    index = index - len(entry['measurements'])
                measurement = entry['measurements'][index]
                break

        if not measurement:
            raise NotImplementedError('Unable to match sensor {uid_high},{uid_low} with measurements')

        # Generate measurement message based on sensor data type
        if data_type == DataType.PROXIMITY.value:
            measurement_response = SensorProximity.SscProximityResponse()
            measurement_response.near = measurement['near']
            measurement_response.distance = measurement['distance']
        elif data_type == DataType.ACCELEROMETER.value:
            measurement_response = SensorAccelerometer.SscAccelerometerResponse()
            for m in measurement['acceleration']:
                measurement_response.acceleration.append(m)
        elif data_type == DataType.MAGNETOMETER.value:
            measurement_response = SensorMagnetometer.SscMagnetometerResponse()
            for m in measurement['magnetic_field']:
                measurement_response.magnetic_field.append(m)
        elif data_type == DataType.LIGHT.value:
            measurement_response = SensorLight.SscLightResponse()
            for m in measurement['intensity']:
                measurement_response.intensity.append(m)
        elif data_type == DataType.ROTATIONVECTOR.value:
            measurement_response = SensorCompass.SscRotationvectorResponse()
            for m in measurement['rotation']:
                measurement_response.rotation.append(m)
        else:
            raise NotImplementedError(f'Unsupported sensor {uid_high},{uid_low} for measurement generation')
        
        measurement_response.accuracy = measurement['accuracy']

        # Protobuf envelope to pack measurement message
        client_response_body = SscCommon.SscClientResponseBody()
        client_response_body.msg = measurement_response.SerializeToString()
        client_response_body.msg_id = measurement['id']
        client_response_body.timestamp = int(time.time())

        client_response = SscCommon.SscClientResponse()
        client_response.response.append(client_response_body)
        client_response.uid.high = uid_high 
        client_response.uid.low = uid_low

        protobuf = client_response.SerializeToString()
        return protobuf

    @staticmethod
    def generate_report_large_indication(data: bytes, transaction_id: int) -> bytes:
        """
        Instantiates a QMI SSC Report Large as a QMI indication.

        Parameters
        ----------
        data : bytes
            Protobuf binary data to pass along.
        transaction_id : int
            QMI transaction ID to use for replies.

        Returns
        -------
        msg : bytes
            The indication message as bytes.
        """
        message = QMI.generate_header(MessageType.INDICATION,
                                      transaction_id,
                                      SSC_REPORT_LARGE_MSG_ID)

        # SSC Client ID
        value = bytes()
        value += int(SSC_CLIENT_ID).to_bytes(8, byteorder='little')
        message = QMI.generate_tlv(message, SSC_REPORT_LARGE_CLIENT_ID, value, ValueType.INT)

        # SSC Data
        message = QMI.generate_tlv(message, SSC_REPORT_LARGE_DATA, data, ValueType.ARRAY)

        return message

    @staticmethod
    def generate_report_small_indication(data: bytes, transaction_id: int) -> bytes:
        """
        Instantiates a QMI SSC Small Large as a QMI indication.

        Parameters
        ----------
        data : bytes
            Protobuf binary data to pass along.
        transaction_id : int
            QMI transaction ID to use for replies.

        Returns
        -------
        msg : bytes
            The indication message as bytes.
        """
        message = QMI.generate_header(MessageType.INDICATION,
                                      transaction_id,
                                      SSC_REPORT_SMALL_MSG_ID)

        # SSC Client ID
        value = bytes()
        value += int(SSC_CLIENT_ID).to_bytes(4, byteorder='little')
        message = QMI.generate_tlv(message, SSC_REPORT_SMALL_CLIENT_ID, value, ValueType.INT)

        # SSC Data
        message = QMI.generate_tlv(message, SSC_REPORT_SMALL_DATA, data, ValueType.ARRAY)

        return message
