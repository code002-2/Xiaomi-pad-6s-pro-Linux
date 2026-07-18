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

libssc_glib_inc = include_directories('.')

version_header = configure_file(
  input: 'libssc-version-private.h.in',
  output: '@BASENAME@',
  configuration: version_conf,
  install_dir: libssc_glib_pkgincludedir,
)

headers += files(
  'libssc.h',
  'libssc-sensor.h',
  'libssc-sensor-proximity.h',
  'libssc-sensor-light.h',
  'libssc-sensor-accelerometer.h',
  'libssc-sensor-magnetometer.h',
  'libssc-sensor-compass.h',
  'libssc-sensor-gyroscope.h',
)

install_headers(
  headers, 
  install_dir: libssc_glib_pkgincludedir
)

sources += files(
  'libssc-common.c',
  'libssc-client.c',
  'libssc-sensor.c',
  'libssc-sensor-proximity.c',
  'libssc-sensor-light.c',
  'libssc-sensor-accelerometer.c',
  'libssc-sensor-magnetometer.c',
  'libssc-sensor-compass.c',
  'libssc-sensor-gyroscope.c',
)

cli_sources = files(
  'libssc-cli.c',
)

so_version = '1'

libssc = library(
  'ssc',
  sources: sources,
  include_directories: includes,
  dependencies: deps,
  install: true,
  soversion: so_version,
)

ssccli = executable(
  'ssccli',
  sources: cli_sources,
  include_directories: includes,
  dependencies: deps,
  link_with: libssc,
  install: true,
)

ns = 'SSC'

pkg.generate(
  libraries: libssc,
  version: libssc_version,
  name: 'libssc',
  description: 'Library to access sensors of Qualcomm Sensor Core',
  subdirs: libssc_glib_include_subdir,
  requires: ['glib-2.0', 'gobject-2.0', 'gio-2.0', 'qmi-glib'],
)

if dependency('gobject-introspection-1.0', required: false).found()
  gnome = import('gnome')

  gir_files = gnome.generate_gir(libssc,
    includes: ['GLib-2.0', 'GObject-2.0', 'Gio-2.0', 'Qmi-1.0'],
    sources: [headers, sources],
    namespace: ns,
    symbol_prefix: 'ssc',
    nsversion: so_version,
    export_packages: 'libssc-0',
    header: 'libssc.h',
    install: true,
  )

  if find_program('vapigen', required: false).found()
    gnome.generate_vapi(
      'libssc',
      packages: ['gobject-2.0', 'glib-2.0', 'gio-2.0'],
      sources: gir_files.get(0),
      install: true,
    )
  endif
endif