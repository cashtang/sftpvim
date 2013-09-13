" sftp upload/ download
"
" vim:ts=4:et:sw=4
if !has("python")
    echo "Has no python support"
    finish
endif

if exists("g:sftpvim_load")
    finish
endif

let g:sftpvim_load = 1

function! SftpSync(file_name, is_upload)
    python << EOF
import sys
import traceback
import os
from path import path
import fileinput
import socket
import paramiko
import vim

class SftpSyncClass(object):
    CONFIG_FILENAME = '.sftpcfg'
    def __init__(self):
        pass

    def message(self, msg):
        print msg
        sys.stdout.flush()

    def run(self, files, upload=True):
        for f in files:
            file_path = path(f).realpath()
            result = self._find_config_recursive(file_path)
            if not result:
                self.message(u"File <{0}> not under sftp config".format(f))
                return
            config_file, relative_path = result
            remote_config = self._load_config(config_file)
            dest_file = path(remote_config['remote']) / relative_path
            dest_file = unicode(dest_file)
            file_path = unicode(file_path)
            ret, msg = self._transfer_file(remote_config, file_path,
                                           dest_file, upload)
            if not ret:
                self.message(u"Upload Error :<{0}>".format(msg))
                return

    def _find_config_recursive(self, dest_file):
        dest_path = dest_file.realpath().dirname()
        found = False
        while 1:
            config_path = dest_path / self.CONFIG_FILENAME
            if config_path.exists():
                found = True
                break
            parent_path = dest_path.parent
            if dest_path == parent_path:
                return None
            dest_path = parent_path
        if not found:
            return None
        relative_path = dest_path.relpathto(dest_file)
        return config_path, relative_path

    def _load_config(self, config_file):
        lineno = 0
        config = {}
        for line in fileinput.input(config_file):
            lineno += 1
            line = line.strip('\n').lstrip(' ')
            if not line:
                continue
            param = line.split('=')
            if not param or len(param) != 2:
                raise ValueError(u"config file error! line : {0}".format(lineno))
            config[param[0].strip(' ')] = param[1].lstrip(' ')
        return config

    def _transfer_file(self, config, src_path, dest_path, upload):
        hostkeytype = None
        hostkey = None
        host_keys = self._load_host_keys()
        if host_keys.has_key(config['host']):
            hostkeytype = host_keys[config['host']].keys()[0]
            hostkey = host_keys[config['host']][hostkeytype]

        self.message(u"wait connect to remote...")
        sock = None
        timeout = config.get('timeout', 5)
        port = config.get('port', 22)
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            sock.connect((config['host'], port))
        except socket.error as e:
            msg = u"Connect error,<{0}>".format(e)
            return False, msg

        try:
            t = paramiko.Transport(sock)
            t.connect(username=config['user'], password=config['password'], hostkey=hostkey)
            self.message(u"Connect remote success!")
            sftp = paramiko.SFTPClient.from_transport(t)
            self._transform(sftp, [(src_path, dest_path)])
            t.close()
            return True, 'OK'
        except BaseException as e:
            traceback.print_exc()
            msg = u"Upload Error,<{0}>".format(e)
            return False, msg

    def _load_host_keys(self):
        try:
            host_keys = paramiko.util.load_host_keys(os.path.expanduser('~/.ssh/known_hosts'))
        except IOError:
            try:
                host_keys = paramiko.util.load_host_keys(os.path.expanduser('~/ssh/known_hosts'))
            except IOError:
                return {}
        return host_keys

    def _transform(self, sftp, file_list):
        for src, dst in file_list:
            dst_dir = os.path.dirname(dst)
            try:
                sftp.mkdir(dst_dir)
            except IOError:
                pass
            self.message(u"Upload file <{0}>".format(src))
            self.message(u"Target <{0}>".format(dst))
            sftp.put(src, dst)

def do_main(file_name, upload):
    sftp = SftpSyncClass()
    sftp.run(file_name, upload)

file_path = vim.eval('a:file_name')
is_upload = vim.eval('a:is_upload')
upload = True if is_upload else False
args = (file_path,)
do_main(args, upload)

EOF
endfunction

command! Sftpupload :call SftpSync(expand('%:p'), 1)
command! Sftpdownload :call SftpSync(expand('%:p'), 0)

