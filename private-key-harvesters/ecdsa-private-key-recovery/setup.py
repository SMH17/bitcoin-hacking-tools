#!/usr/bin/env python
# -*- coding: utf-8 -*-

import os
from setuptools import setup, find_packages


def read(fname):
    return open(os.path.join(os.path.dirname(__file__), fname)).read()


version = "0.1.0"

setup(
    name="ecdsa-private-key-recovery",
    version=version,
    packages=find_packages(),
    author="tintinweb",
    author_email="tintinweb@oststrom.com",
    description=(
        "A simple library to recover the private key of ECDSA and DSA signatures sharing the same nonce k and therefore having identical signature parameter r"),
    license="GPLv2",
    keywords=["ecdsa", "dsa", "recovery", "nonce", "blockchain"],
    url="https://github.com/tintinweb/ecdsa-private-key-recovery",
    download_url="https://github.com/tintinweb/ecdsa-private-key-recovery/tarball/v%s"%version,
    #python setup.py register -r https://testpypi.python.org/pypi
    long_description=read("README.md") if os.path.isfile("README.md") else "",
    long_description_type='text/markdown',
    install_requires=["pycryptodomex",
                      "pycrypto",
                      "ecdsa"],
)
