#!/usr/bin/env python
# -*- coding: utf-8 -*-
# author: github.com/tintinweb

from Crypto.Random import random
from Crypto.Hash import SHA
from Crypto.PublicKey import DSA

from ecdsa_key_recovery import DsaSignature, EcDsaSignature

import ecdsa

import logging

logger = logging.getLogger(__name__)


def bignum_to_hex(val, nbits=256):
    ret = hex((val + (1 << nbits)) % (1 << nbits)).rstrip("L").lstrip("0x")
    if len(ret) % 2 == 1:
        # even out hexstr
        return "0" + ret
    return ret


# noinspection PyClassHasNoInit
class Tests:
    # noinspection PyClassHasNoInit
    class EcDsa:

        @staticmethod
        def test_nonce_reuse_importkey():
            secret_key = """-----BEGIN EC PRIVATE KEY-----
MHQCAQEEIOdzzzX85WfQYiIDwo9nR4ozYbrn5utDZrUOHSfrHtguoAcGBSuBBAAK
oUQDQgAEpQ62aIfQP+GGtgj0d9mbx2McVuZLs699yX5xuRfFs2R5VNo0RNM7jR+Q
oNcWiy8ViiyW20ZzMoZhn8yq+6ymvA==
-----END EC PRIVATE KEY-----"""
            return Tests.EcDsa.test_nonce_reuse(EcDsaSignature.import_key(secret_key).get_verifying_key().pubkey)

        @staticmethod
        def test_nonce_reuse(pub=None, curve=ecdsa.SECP256k1):
            if not pub:
                # default
                pub = ecdsa.VerifyingKey.from_string(
                    "a50eb66887d03fe186b608f477d99bc7631c56e64bb3af7dc97e71b917c5b3647954da3444d33b8d1f90a0d7168b2f158a2c96db46733286619fccaafbaca6bc".decode(
                        "hex"), curve=curve).pubkey
            # static testcase
            # long r, long s, bytestr hash, pubkey obj.
            sampleA = EcDsaSignature((3791300999159503489677918361931161866594575396347524089635269728181147153565,
                                      49278124892733989732191499899232294894006923837369646645433456321810805698952),
                                     bignum_to_hex(
                                         765305792208265383632692154455217324493836948492122104105982244897804317926).decode(
                                         "hex"),
                                     pub)
            sampleB = EcDsaSignature((3791300999159503489677918361931161866594575396347524089635269728181147153565,
                                      34219161137924321997544914393542829576622483871868414202725846673961120333282),
                                     bignum_to_hex(
                                         23350593486085962838556474743103510803442242293209938584974526279226240784097).decode(
                                         "hex"),
                                     pub)

            assert (sampleA.x is None)  # not yet resolved
            logger.debug("%r - recovering private-key from nonce reuse ..." % sampleA)
            sampleA.recover_nonce_reuse(sampleB)
            assert (sampleA.x is not None)  # privkey recovered
            assert sampleA.privkey
            logger.debug("%r - Private key recovered! \n%s" % (sampleA, sampleA.export_key()))

    # noinspection PyClassHasNoInit
    class Dsa:

        @staticmethod
        def signMessage(privkey, msg, k=None):

            """
            create DSA signed message
            @arg privkey ... privatekey as DSA obj
            @arg msg     ... message to sign
            @arg k       ... override random k
            """

            k = k or random.StrongRandom().randint(2, privkey.q - 1)
            # generate msg hash
            # sign the messages using privkey
            h = SHA.new(msg).digest()
            r, s = privkey.sign(h, k)
            return h, (r, s), privkey.publickey()

        @staticmethod
        def test_nonce_reuse_importkey():
            secret_key = """-----BEGIN PRIVATE KEY-----
                        MIIBSwIBADCCASsGByqGSM44BAEwggEeAoGBAIAAAAAAAAAARApDBH1CEeZPeIM9
                        mMb6l3FyY8+AOy+cdiDzCaqlkIRVIRRxvnCH5oJ6gkinosGscZMTgF7IwQJzDHFm
                        oxvVdpACrj5Je+kpF6djefAbe+ByZ4FowkGq1EdMZF8aZzsik3CFkEA/vDsjvAsg
                        XmKRvOnFHkkFuKCRAhUA/+rcmBQ71NBsDzkbusi6NQpTNF8CgYAFVt8xSXTiCGn8
                        +bqWyoX+gjItArrT28o6fGnq+apjwasvWDHq1FETk/gwqTbTwWTiMo2eOTImRKDF
                        MbK1us+DjhloAUuhL6nCRQhsLs4Jq+8A/y7aol/HjCz1fHRKKDD9wqKDf2kWdI97
                        Kb2Hq4AUoJWTCT0ijX+oQJafbywjdwQXAhUAniK/kyRv/SFd1uJjuDMh0EntMws=
                        -----END PRIVATE KEY-----"""
            return Tests.Dsa.test_nonce_reuse(DsaSignature.import_key(secret_key))

        @staticmethod
        def test_nonce_reuse(secret_key=DSA.generate(1024)):
            # choose a "random" - k :)  this time random is static in order to allow this attack to work
            k = random.StrongRandom().randint(1, secret_key.q - 1)
            # sign two messages using the same k
            samples = (Tests.Dsa.signMessage(secret_key, "This is a signed message!", k),
                       Tests.Dsa.signMessage(secret_key, "Another signed Message -  :)", k))
            logger.debug("generated sample signatures: %s" % repr(samples))
            signatures = [DsaSignature(sig, h, pubkey) for h, sig, pubkey in samples]
            logger.debug("Signature Objects: %r" % signatures)

            two_sigs = []
            for sig in signatures:
                two_sigs.append(sig)
                if not len(two_sigs) == 2:
                    continue
                sample = two_sigs.pop(0)
                logger.debug("%r - recovering privatekey from nonce reuse..." % sample)
                assert (sample.x is None)  # not yet resolved
                sample.recover_nonce_reuse(two_sigs[0])
                assert (sample.x is not None)  # privkey recovered
                assert (sample.privkey == secret_key)
                logger.debug("%r - Private key recovered! \n%s" % (sample, sample.export_key()))


if __name__ == "__main__":
    logging.basicConfig(loglevel=logging.DEBUG)
    logger.setLevel(logging.DEBUG)
    logging.getLogger("ecdsa_dsa_crack").setLevel(logging.DEBUG)
    logger.info("------------EcDSA------------")
    Tests.EcDsa.test_nonce_reuse()
    Tests.EcDsa.test_nonce_reuse_importkey()
    logger.info("------------DSA------------")
    Tests.Dsa.test_nonce_reuse()
    Tests.Dsa.test_nonce_reuse_importkey()
