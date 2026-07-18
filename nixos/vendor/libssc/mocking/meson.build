pymod = import('python')
python = pymod.find_installation()
python.dependency()

mocking_sources = files(
  'qmi.py',
  'ssc.py',
)

python.install_sources(mocking_sources)

install_data('ssc-server', install_dir: get_option('bindir'))
install_data('ssc-server-tests', install_dir: get_option('bindir'))
