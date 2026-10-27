"""Serve local good/expired/wrong-host/self-signed TLS media endpoints.

提供合法、过期、主机名不符及自签名本地TLS媒体服务。
"""
from pathlib import Path
import http.server
import ssl
import subprocess
import threading
import functools
import time

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'coverage_tls'
OUT.mkdir(exist_ok=True)
OPENSSL='C:/Program Files/Git/mingw64/bin/openssl.exe'


def openssl(*args):
    """Create disposable certificates only inside the allowed tool directory.

    只在允许的tool目录创建临时测试证书。
    """
    subprocess.run([OPENSSL,*args],cwd=OUT,check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)


if not (OUT/'ca.pem').exists():
    openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout','ca.key','-out','ca.pem','-days','30','-subj','/CN=Mova Coverage CA')
if not (OUT/'self.pem').exists():
    for name,host,days in [('good','IP:127.0.0.1','10'),('expired','IP:127.0.0.1','10'),('wrong','DNS:wrong.invalid','10')]:
        openssl('req','-newkey','rsa:2048','-nodes','-keyout',name+'.key','-out',name+'.csr','-subj','/CN='+name)
        (OUT/(name+'.ext')).write_text('subjectAltName='+host+'\nextendedKeyUsage=serverAuth\n')
        if name=='expired':
            (OUT/'index.txt').write_text('')
            (OUT/'serial').write_text('01\n')
            (OUT/'expired.cnf').write_text('[ca]\ndefault_ca=c\n[c]\ndatabase=index.txt\nnew_certs_dir=.\nserial=serial\ndefault_md=sha256\npolicy=policy\ncertificate=ca.pem\nprivate_key=ca.key\ndefault_days=10\nx509_extensions=ext\n[policy]\ncommonName=supplied\n[ext]\nsubjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n')
            openssl('ca','-config','expired.cnf','-batch','-startdate','20200101000000Z','-enddate','20210101000000Z','-in','expired.csr','-out','expired.pem')
        else:
            openssl('x509','-req','-in',name+'.csr','-CA','ca.pem','-CAkey','ca.key','-CAcreateserial','-out',name+'.pem','-days',days,'-extfile',name+'.ext')
    openssl('req','-x509','-newkey','rsa:2048','-nodes','-keyout','self.key','-out','self.pem','-days','10','-subj','/CN=self','-addext','subjectAltName=IP:127.0.0.1')
(ROOT/'coverage_media/ca.pem').write_bytes((OUT/'ca.pem').read_bytes())
if not (OUT/'good_dns.pem').exists():
    openssl('req','-newkey','rsa:2048','-nodes','-keyout','good_dns.key','-out','good_dns.csr','-subj','/CN=localhost')
    (OUT/'good_dns.ext').write_text('subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n')
    openssl('x509','-req','-in','good_dns.csr','-CA','ca.pem','-CAkey','ca.key','-CAcreateserial','-out','good_dns.pem','-days','10','-extfile','good_dns.ext')
servers=[]
for port,name in enumerate(['good','expired','wrong','self','good_dns'],18443):
    server=http.server.ThreadingHTTPServer(('127.0.0.1',port),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(ROOT/'coverage_media')))
    context=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(OUT/(name+'.pem'),OUT/(name+'.key'))
    server.socket=context.wrap_socket(server.socket,server_side=True)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    servers.append(server)
print('COVERAGE_TLS_READY 18443-18446',flush=True)
while True:
    time.sleep(1)
