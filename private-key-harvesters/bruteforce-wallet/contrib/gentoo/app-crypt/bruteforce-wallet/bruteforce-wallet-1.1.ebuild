# Copyright 2014 Guillaume LE VAILLANT
# Distributed under the terms of the GNU General Public License v3

EAPI="5"

inherit eutils autotools

DESCRIPTION="A bruteforce cracker for Peercoin (and Bitcoin, Litecoin, etc...) encrypted wallet files."
HOMEPAGE="https://github.com/glv2/${PN}"
SRC_URI="https://github.com/glv2/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64 ~arm ~x86"

DEPEND="
	dev-libs/openssl
	sys-libs/db
"
RDEPEND="${DEPEND}"

src_prepare() {
	eautoreconf
}

src_configure() {
	econf
}

src_install() {
	dobin "${PN}"
	dodoc AUTHORS ChangeLog COPYING NEWS README
}
