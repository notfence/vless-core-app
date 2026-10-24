import binascii
from pathlib import Path
import re
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]

def validate(root=ROOT):
    records=[]
    for line in (root/'tests/flag_sequences.txt').read_text().splitlines():
        values,status,asset=line.split(';')
        records.append((tuple(int(cp,16) for cp in values.split()),status,asset))
    assets={asset for _,_,asset in records}
    assert len(assets)==268 and len(records)==270, 'flags/repertoire'
    table=(root/'common/flag_data.h').read_text()
    generated=[]
    for values,count,asset in re.findall(r'\{\{([^}]+)\}, (\d+), "([a-z0-9-]+)"\}',table):
        points=tuple(int(cp.strip(),16) for cp in values.split(','))
        assert len(points)==int(count) and len(points)<=8
        generated.append((points,asset))
    assert generated==sorted((values,asset) for values,_,asset in records), 'flags/table-fixture-match'
    directory=root/'app/icons/flags'
    assert {p.stem for p in directory.iterdir()}==assets, 'flags/exact-image-set'
    total=0
    for asset in assets:
        data=(directory/(asset+'.png')).read_bytes(); total+=len(data)
        assert data.startswith(b'\x89PNG\r\n\x1a\n'), asset
        position=8; compressed=bytearray(); ihdr=None; ended=False
        while position<len(data):
            length=struct.unpack_from('>I',data,position)[0]
            kind=data[position+4:position+8]; body=data[position+8:position+8+length]
            crc=struct.unpack_from('>I',data,position+8+length)[0]
            assert binascii.crc32(kind+body)&0xffffffff==crc, asset
            if kind==b'IHDR': ihdr=struct.unpack('>IIBBBBB',body)
            if kind==b'IDAT': compressed.extend(body)
            if kind==b'IEND': ended=True
            position+=12+length
        assert position==len(data) and ended and ihdr[:2]==(72,72) and ihdr[3] in (2,3,6) and ihdr[4:]==(0,0,0), (asset,ihdr)
        pixels=zlib.decompress(compressed)
        channels={2:3,3:1,6:4}[ihdr[3]]
        assert len(pixels)==72*(1+(72*channels*ihdr[2]+7)//8), asset
    renderer=(root/'app/flag_label.m').read_text()
    for forbidden in ('imageNamed:', 'method_exchangeImplementations', 'NSURLSession', 'NSTimer'):
        assert forbidden not in renderer, forbidden
    for required in ('256*1024','CGImageGetBytesPerRow','UIApplicationDidReceiveMemoryWarningNotification','CTRunDelegateCreate','CTLineCreateTruncatedLine','CTTypesetterSuggestClusterBreak','[super drawTextInRect:rect]','_flagTitleLabel.text=nil; _flagDetailLabel.text=nil;'):
        assert required in renderer, required
    assert 'VCFlagTableCell' in (root/'app/main_cells.h').read_text()
    screen=(root/'app/main_screen.m').read_text()
    assert '_selectionLabel = [[VCFlagLabel alloc]' in screen and '_statusLabel = [[VCFlagLabel alloc]' in screen
    info=(root/'app/subscription_info.m').read_text()
    assert 'VCFlagTextSize' in info and 'nameRow ? [VCFlagTableCell class]' in info
    assert 'flag_' not in (root/'common/profile_logic.m').read_text()
    legal=(root/'legal/THIRD_PARTY_LICENSES.txt').read_text()
    assert 'Twemoji 17.0.3 flag graphics' in legal and 'Unicode Emoji 17.0 data' in legal
    print(f'PASS flag assets: {len(assets)} images, {len(records)} sequences, {total} PNG bytes; UI integration contracts')

if __name__=='__main__':
    try: validate()
    except (AssertionError,OSError,ValueError,struct.error,zlib.error) as error:
        sys.exit('FAIL flag assets/'+str(error))
