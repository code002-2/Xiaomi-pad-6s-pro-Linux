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
from enum import Enum
from typing import Tuple


class ValueType(Enum):
    INT = 0
    ARRAY = 1
    SEQUENCE = 2


class MessageType(Enum):
    REQUEST = 0
    RESPONSE = 2
    INDICATION = 4
    UNKNOWN = sys.maxsize


class QMI():
    """QMI messages encoding and decoding functions."""

    @staticmethod
    def parse_header(message: bytes) -> Tuple[MessageType, int, int, bytes]:
        """
        Parse a QMI header to extract:
          - Type of message (uint8)
          - Transaction ID (uint16)
          - Message ID (uint16)
          - Message length (uint16)

        Parameters
        ----------
        message : bytes
            Raw QMI message as bytes (little endian).

        Returns
        -------
        message_type : MessageType
            Type of message e.g., REQUEST, RESPONSE, or INDICATION.
        transaction_id : int
            ID of the transaction for concurrent messages.
        message_id : int
            ID of the message, specific for the QMI service.
        message_length : int
            Length of the message in bytes.
        """

        # QMI message type
        if message[0] == MessageType.REQUEST.value:
            message_type = MessageType.REQUEST
        elif message[0] == MessageType.RESPONSE.value:
            message_type = MessageType.RESPONSE
        elif message[0] == MessageType.INDICATION.value:
            message_type = MessageType.INDICATION
        else:
            print(f'Unknown message type: {message[0]}', file=sys.stderr)
            message_type = MessageType.UNKNOWN 

        # QMI transaction ID
        transaction_id = int.from_bytes(message[1:3], byteorder='little')

        # QMI message ID
        message_id = int.from_bytes(message[3:5], byteorder='little')

        # QMI message length
        message_length = int.from_bytes(message[5:7], byteorder='little')

        return message_type, transaction_id, message_id, message_length

    @staticmethod
    def generate_header(message_type: MessageType, transaction_id: int, message_id: int) -> bytes:
        """
        Generate a QMI message with no TLVs and a QMI header.

        Parameters
        ----------
        message_type : MessageType
            Type of QMI message
        transaction_id : int
            ID of the transaction.
        message_id : int
            ID of the message for the specific QMI service.

        Returns
        -------
        message : bytes
            Raw QMI message as bytes (little endian).
        """

        message = bytes()
        message += message_type.value.to_bytes(1, byteorder='little')
        message += transaction_id.to_bytes(2, byteorder='little')
        message += message_id.to_bytes(2, byteorder='little')
        message += (len(message) + 2).to_bytes(2, byteorder='little')

        return message

    @staticmethod
    def parse_tlv(message: bytes, tlv: int, value_type: ValueType) -> Tuple[int, int, bytes]:
        """
        Parse QMI TLV in a QMI message to extract:
          - Type (uint8)
          - Length (uint16)
          - Value (bytes)

        Parameters
        ----------
        message : bytes
            Raw QMI message as bytes (little endian).

        Returns
        -------
        tlvs : dict
            Dictionary of TLVs extracted with Type as dictionary's key
            and Value as dictionary's value. Length is implied.
        """
        message_type, transaction_id, message_id, message_length = QMI.parse_header(message)

        # Strip QMI header
        tlvs = message[7:]

        # Iterate over all TLVs
        offset = 0
        tlv_id = 0
        while offset < len(tlvs):
            tlv_type = int.from_bytes(tlvs[0+offset:1+offset], byteorder='little')
            tlv_length = int.from_bytes(tlvs[1+offset:3+offset], byteorder='little')
            tlv_value = tlvs[3+offset:3+tlv_length+offset]
            offset += 1 + 2 + tlv_length
            tlv_id += 1

            # Strip array length from QMI TLV value
            if value_type == ValueType.INT or value_type == ValueType.SEQUENCE:
                tlv_value = int.from_bytes(tlv_value, byteorder='little')
            elif value_type == ValueType.ARRAY:
                tlv_value = tlv_value[2:]

            # Look for TLV in message, skip others
            if tlv != tlv_type:
                continue

            return tlv_type, tlv_length, tlv_value

    @staticmethod
    def generate_tlv(message: bytes, tlv_id: int, tlv_value: bytes, value_type: ValueType) -> bytes:
        """
        Generate a QMI TLV and add it to the message.

        Parameters
        ----------
        message : bytes
            Raw QMI message as bytes (little endian).
        tlv_id : int
            TLV Type.
        tlv_value : bytes
            TLV Value.
        value_type : ValueType
            Type of the TLV Value.

        Returns
        -------
        message : bytes
            Raw QMI message as bytes (little endian).
        """
        # Add TLV and calculate its length
        message += tlv_id.to_bytes(1, byteorder='little')

        if value_type == ValueType.ARRAY:
            message += (len(tlv_value) + 2).to_bytes(2, byteorder='little')
        elif value_type == ValueType.INT or value_type == ValueType.SEQUENCE:
            message += len(tlv_value).to_bytes(2, byteorder='little')
        else:
            print(f'Unknown value type: {value_type}', file=sys.stderr)

        if value_type == ValueType.ARRAY:
            value_array_length = len(tlv_value)
            message += value_array_length.to_bytes(2, byteorder='little')

        message += tlv_value

        # Update QMI header length
        qmi_length = int.from_bytes(message[5:7], byteorder='little')
        message = message[:5] + \
                  (len(message) - 7).to_bytes(2, byteorder='little') + \
                  message[7:]

        return message
