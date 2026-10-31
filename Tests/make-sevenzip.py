"""Small synthetic 7z fixtures, built from public 7-Zip format specification.
Uses Python's raw LZMA encoder; no third-party Python packages or CLI required.
"""
import pathlib,sys,struct,zlib,lzma
r=pathlib.Path(sys.argv[1]);r.mkdir(parents=True,exist_ok=True)
def num(n):
 for extra in range(8):
  if n < (1 << (7+7*extra)):
   return bytes([((0xff << (8-extra))&255) | (n >> (8*extra))])+n.to_bytes(8,'little')[:extra]
 return b'\xff'+n.to_bytes(8,'little')
def digest(v):return b'\x01'+b''.join(struct.pack('<I',zlib.crc32(x)) for x in v)
def coder(method='lzma2',dictionary=1<<20):
 if method=='copy':return b'\x01\x00',b'',None
 if method=='lzma1':return b'\x23\x03\x01\x01',b'\x5d'+struct.pack('<I',dictionary),{'id':lzma.FILTER_LZMA1,'dict_size':dictionary,'lc':3,'lp':0,'pb':2}
 if method=='lzma2':
  prop=next(p for p in range(40) if (2|(p&1)) << ((p>>1)+11) >= dictionary)
  return b'\x21\x21',bytes([prop]),{'id':lzma.FILTER_LZMA2,'dict_size':dictionary}
def stream(data,method='lzma2',position=0,parts=None,override_props=None,override_size=None):
 id,props,filter=coder(method)
 packed=data if method=='copy' else lzma.compress(data,format=lzma.FORMAT_RAW,filters=[filter])
 props=props if override_props is None else override_props
 code=b'\x01'+id+(num(len(props))+props if props else b'')
 h=b'\x06'+num(position)+b'\x01\x09'+num(len(packed))+b'\x0a'+digest([packed])+b'\x00'
 h+=b'\x07\x0b\x01\x00'+code+b'\x0c'+num(len(data) if override_size is None else override_size)+b'\x0a'+digest([data])+b'\x00'
 if parts is not None:
  h+=b'\x08\x0d'+num(len(parts))+b'\x09'+b''.join(num(len(p)) for p in parts[:-1])+b'\x0a'+digest(parts)+b'\x00'
 return h+b'\x00',packed
def fileinfo(names,attr=None):
 names=b'\x00'+b''.join(n.encode('utf-16le')+b'\x00\x00' for n in names)
 # explicit file count passed through number of terminating UTF16 NULs
 count=sum(names[i:i+2]==b'\x00\x00' for i in range(1,len(names),2))
 p=b'\x05'+num(count)+b'\x11'+num(len(names))+names
 if attr is not None:
  attrs=b'\x01\x00'+b''.join(struct.pack('<I',attr) for _ in range(count));p+=b'\x15'+num(len(attrs))+attrs
 return p+b'\x00'
def wrap(header,packed=b''):
 start=struct.pack('<QQI',len(packed),len(header),zlib.crc32(header));return b'7z\xbc\xaf\x27\x1c\x00\x04'+struct.pack('<I',zlib.crc32(start))+start+packed+header
def make(names=['nested/你好.txt'],parts=[b'hello'],method='lzma2',encoded=False,props=None,size=None,attr=None):
 s,packed=stream(b''.join(parts),method,parts=parts if len(parts)>1 else None,override_props=props,override_size=size)
 h=b'\x01\x04'+s+fileinfo(names,attr)+b'\x00'
 if encoded:
  hs,hp=stream(h,'lzma1',position=len(packed));return wrap(b'\x17'+hs,packed+hp)
 return wrap(h,packed)
for method in ['copy','lzma1','lzma2']:(r/(method+'.7z')).write_bytes(make(method=method))
(r/'encoded.7z').write_bytes(make(encoded=True))
(r/'solid.7z').write_bytes(make(['nested/a.txt','nested/你好.txt'],[b'a'*100,b'hello'],encoded=True))
(r/'empty.7z').write_bytes(wrap(b'\x01\x00'))
for name,path in [('traversal','../escape'),('absolute','/tmp/escape'),('deep','/'.join(['a']*65)),('backslash','a\\b')]:(r/(name+'.7z')).write_bytes(make([path]))
(r/'dictionary.7z').write_bytes(make(props=b'\x28'))
(r/'lzma1-dictionary.7z').write_bytes(make(method='lzma1',props=b'\x5d\xff\xff\xff\x7f'))
(r/'oversize.7z').write_bytes(make(size=129*1024*1024))
(r/'duplicate.7z').write_bytes(make(['x','x'],[b'a',b'b']))
(r/'symlink.7z').write_bytes(make(attr=(0xa1ff<<16)|0x8000))
(r/'reparse.7z').write_bytes(make(attr=0x400))
(r/'conflict.7z').write_bytes(make(['x','x/child'],[b'a',b'b']))
b=bytearray(make());b[8]^=1;(r/'startcrc.7z').write_bytes(b)
b=bytearray(make());b[-2]^=1;(r/'headercrc.7z').write_bytes(b)
b=bytearray(make());b[32]^=255;(r/'datacrc.7z').write_bytes(b)
(r/'truncated.7z').write_bytes(make()[:-7])
(r/'metadata.7z').write_bytes(wrap(b'x'*(1024*1024+1)))
(r/'count.7z').write_bytes(wrap(b'\x01\x05'+num(20001)+b'\x00\x00'))
(r/'integer.7z').write_bytes(wrap(b'\x01\x05'+num((1<<64)-1)))
# Replace allowed coder with AES method, retaining checksummed outer headers.
s,p=stream(b'hello');s=s.replace(b'\x21\x21\x01\x10',b'\x24\x06\xf1\x07\x01\x01\x10')
(r/'encrypted.7z').write_bytes(wrap(b'\x01\x04'+s+fileinfo(['secret'])+b'\x00',p))
h,p=stream(b'x',override_size=1024*1024+1);(r/'headerbomb.7z').write_bytes(wrap(b'\x17'+h,p))
# Raw header malformed after correct CRC, metadata payloads still bounded.
(r/'invalidutf16.7z').write_bytes(wrap(b'\x01\x05\x01\x11\x05\x00\x00\xd8\x00\x00\x00\x00'))

(r/'large.7z').write_bytes(make(['large.txt'],[b'0'*(8*1024*1024)]))
