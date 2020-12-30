#!/usr/bin/env python
# -*- coding: utf-8 -*-
# author: github.com/tintinweb
"""
EcDSA/DSA Nonce Reuse Private Key Recovery
"""

import Crypto
from Crypto.PublicKey import DSA
from Crypto.PublicKey.pubkey import inverse
import Cryptodome.PublicKey.DSA
import Cryptodome.PublicKey.ECC

import ecdsa
from ecdsa import SigningKey
from ecdsa.numbertheory import inverse_mod

import logging

logger = logging.getLogger(__name__)


# noinspection PyProtectedMember,PyProtectedMember,PyProtectedMember,PyProtectedMember,PyProtectedMember
def to_dsakey(secret_key, _from=Crypto.PublicKey.DSA, _to=Cryptodome.PublicKey.DSA):
    if _from == Cryptodome.PublicKey.DSA:
        return _to.construct((int(secret_key._key['y']),
                              int(secret_key._key['g']),
                              int(secret_key._key['p']),
                              int(secret_key._key['q']),
                              int(secret_key._key['x'])))
    return _to.construct((secret_key.key.y,
                          secret_key.key.g,
                          secret_key.key.p,
                          secret_key.key.q,
                          secret_key.key.x))


def to_ecdsakey(secret_key, _from=ecdsa.SigningKey, _to=Cryptodome.PublicKey.ECC):
    # pointx, pointy, d
    return _to.import_key(secret_key.to_der())


class SignatureParameter(object):
    """
    DSA signature parameters.
    """

    def __init__(self, r, s):
        """

        :param r: Signature Param r
        :param s: Signature Param s
        """
        self.r = r
        self.s = s

    @property
    def tuple(self):
        """
        Signature parameter to tuple()
        :return: tuple(r,s)
        """
        return self.r, self.s


class RecoverableSignature(object):
    """
    A BaseClass for a recoverable EC/DSA Signature.
    """

    def __init__(self, sig, h, pubkey):
        """

        :param sig: tuple(long r, long s)
        :param h: bytestring message digest
        :param pubkey: pubkey object
        """
        self.sig = self._load_signature(sig)
        self.h = self._load_hash(h)
        self.pubkey = self._load_pubkey(pubkey)
        self.k = None
        self.x = None

    def __repr__(self):
        return "<%s 0x%x sig=%s public=%s private=%s >" % (self.__class__.__name__,
                                                           hash(self),
                                                           "(%s,%s)" % (
                                                               str(self.sig.r)[:10] + "…", str(self.sig.s)[:10] + "…"),
                                                           "✔" if self.pubkey else '⨯',
                                                           "✔" if self.x else '⨯')

    def _load_signature(self, sig):
        if all(hasattr(sig, att) for att in ('r','s')):
            return sig
        elif isinstance(sig, tuple):
            return SignatureParameter(*sig)

        raise ValueError("Invalid Signature Format! - Expected tuple(long r,long s) or SignatureParamter(long r, long s)")

    def _load_hash(self, h):
        if isinstance(h, (int, long)):
            return h
        elif isinstance(h, basestring):
            return Crypto.Util.number.bytes_to_long(h)

        raise ValueError("Invalid Hash Format! - Expected long(hash) or str(hash)")

    def _load_pubkey(self, pubkey):
        raise NotImplementedError("Must be implemented by subclass")



    def recover_nonce_reuse(self, other):
        """
        PrivateKey recovery from Signatures with reused nonce *k*.
        Note: a reused *k* results in the same value for *r* for both signatures
        :param other: other object of same type
        :return: self
        """
        raise NotImplementedError("%s cannot be called directly" % self.__class__.__name__)

    def export_key(self, *args, **kwargs):
        raise NotImplementedError("%s cannot be called directly" % self.__class__.__name__)

    def import_key(self, *args, **kwargs):
        raise NotImplementedError("%s cannot be called directly" % self.__class__.__name__)


class DsaSignature(RecoverableSignature):
    """
    Implementation of a DSA Signature
    """

    def __init__(self, sig, h, pubkey):
        super(DsaSignature, self).__init__(sig, h, pubkey)
        logger.debug("%r - check verifies.." % self)
        assert self.pubkey.verify(self.h, self.sig.tuple)  # check sig verifies hash
        logger.debug("%r - Signature is ok" % self)

    def _load_pubkey(self, pubkey):
        return pubkey

    def export_key(self, *args, **kwargs):
        # format='PEM', pkcs8=None, passphrase=None, protection=None, randfunc=None
        return to_dsakey(self.privkey, _to=Cryptodome.PublicKey.DSA).exportKey(*args, **kwargs)

    @staticmethod
    def import_key(*args, **kwargs):
        # extern_key, passphrase=None
        key = Cryptodome.PublicKey.DSA.import_key(*args, **kwargs)
        return to_dsakey(key, _from=Cryptodome.PublicKey.DSA, _to=Crypto.PublicKey.DSA)

    @property
    def privkey(self):
        """
        Reconstructs a DSA Signature Object
        :return: DSA Private Key Object
        """
        assert self.x  # privkey must be recovered fist
        return DSA.construct([self.pubkey.y,
                              self.pubkey.g,
                              self.pubkey.p,
                              self.pubkey.q,
                              self.x])

    def recover_nonce_reuse(self, other):
        assert (self.pubkey.q == other.pubkey.q)
        assert (self.sig.r == other.sig.r)  # reused *k* implies same *r*
        self.k = (self.h - other.h) * inverse(self.sig.s - other.sig.s, self.pubkey.q) % self.pubkey.q
        self.x = ((self.k * self.sig.s - self.h) * inverse(self.sig.r, self.pubkey.q)) % self.pubkey.q
        # other.k, other.x = self.k, self.x   # update other object as well?
        return self


class EcDsaSignature(RecoverableSignature):

    def __init__(self, sig, h, pubkey, curve=ecdsa.SECP256k1):
        self.curve = curve  # must be set before __init__ calls __load_pubkey

        super(EcDsaSignature, self).__init__(sig, h, pubkey)

        self.signingkey = None
        self.n = self.pubkey.generator.order()

        logger.debug("%r - check verifies.." % self)
        assert (self.pubkey.verifies(self.h, self.sig))
        logger.debug("%r - Signature is ok" % self)

    def _load_pubkey(self, pubkey):
        if isinstance(pubkey, ecdsa.ecdsa.Public_key):
            return pubkey
        elif isinstance(pubkey, basestring):
            return ecdsa.VerifyingKey.from_string(pubkey, curve=self.curve).pubkey
        return pubkey

    def export_key(self, *args, **kwargs):
        # format='PEM', pkcs8=None, passphrase=None, protection=None, randfunc=None
        ext_format = kwargs.get("format", "PEM")
        if ext_format == "PEM":
            return self.signingkey.to_pem()
        elif ext_format == "DER":
            return self.signingkey.to_der()
        raise ValueError("Unknown format '%s'" % ext_format)

    @staticmethod
    def import_key(encoded, passphrase=None):
        # encoded, passphrase=None
        # extern_key, passphrase=None
        # key = Cryptodome.PublicKey.ECC.import_key(*args, **kwargs)
        # return to_ecdsakey(key, _from=Cryptodome.PublicKey.ECC, _to=ecdsa.SigningKey)

        if encoded.startswith('-----'):
            return ecdsa.SigningKey.from_pem(encoded)

        # OpenSSH
        # if encoded.startswith(b('ecdsa-sha2-')):
        #    return _import_openssh(encoded)
        # DER
        if ord(encoded[0]) == 0x30:
            return ecdsa.SigningKey.from_der(encoded)
        raise Exception("Invalid Format")

    @property
    def privkey(self):
        """
        Reconstructs a DSA Signature Object
        :return: DSA Private Key Object
        """
        assert self.x  # privkey must be recovered fist
        assert self.signingkey
        return self.signingkey.privkey

    def recover_nonce_reuse(self, other):
        sig2 = other.sig  # rename it
        h2 = other.h  # rename it
        # precalculate static values
        z = self.h - h2
        r_inv = inverse_mod(self.sig.r, self.n)
        #
        # try all candidates
        #
        for candidate in (self.sig.s - sig2.s,
                          self.sig.s + sig2.s,
                          -self.sig.s - sig2.s,
                          -self.sig.s + sig2.s):
            k = (z * inverse_mod(candidate, self.n)) % self.n
            d = (((self.sig.s * k - self.h) % self.n) * r_inv) % self.n
            signingkey = SigningKey.from_secret_exponent(d, curve=self.curve)
            if signingkey.get_verifying_key().pubkey.verifies(self.h, self.sig):
                self.signingkey = signingkey
                self.k = k
                self.x = d
                return self
        assert False  # could not recover private key
