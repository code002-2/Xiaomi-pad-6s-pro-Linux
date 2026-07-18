# SPDX-License-Identifier: GPL-3.0-or-later
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

msgs_inc = include_directories('.')

msgs = [
  'common',
  'sensor-suid',
  'sensor-proximity',
  'sensor-light',
  'sensor-accelerometer',
  'sensor-magnetometer',
  'sensor-rotationvector',
  'sensor-gyroscope',
]
sources_gen = []
headers_gen = []
python_gen = []

foreach m: msgs
  name = 'ssc-' + m
  # C
  protobuf_c_gen = custom_target (
    name + '_c',
    input: name + '.proto',
    output: [name + '.pb-c.c', name + '.pb-c.h'],
    command: [protocc_tool, '--proto_path=@CURRENT_SOURCE_DIR@', '--c_out=@OUTDIR@', '@INPUT@'],
    install: true,
    install_dir: [false, libssc_glib_pkgincludedir]
  )
  sources_gen += protobuf_c_gen[0]
  headers_gen += protobuf_c_gen[1]

  # Python
  python_name = 'ssc_' + m.replace('-', '_')
  protobuf_python_gen = custom_target (
    python_name + '_py',
    input: name + '.proto',
    output: [python_name + '_pb2.py'],
    command: [protoc_tool, '-I=@CURRENT_SOURCE_DIR@', '--python_out=@OUTDIR@', '@INPUT@'],
    install: true,
    install_dir: [libssc_mocking_dir]
  )
  python_gen += protobuf_python_gen[0]
endforeach

generated_dep = declare_dependency(
  sources: sources_gen + headers_gen + python_gen,
  include_directories: includes,
  dependencies: deps
)
deps += generated_dep
