AC_INIT(bruteforce_wallet, 1.4.1)
AM_INIT_AUTOMAKE
AC_CONFIG_SRCDIR(src/bruteforce-wallet.c)

dnl Check for toolchain and install components
AC_PROG_CC
AC_PROG_INSTALL

dnl Check for standard headers
AC_CHECK_HEADERS([math.h locale.h signal.h stdio.h stdlib.h string.h unistd.h wchar.h])

dnl Check for functions
AC_CHECK_FUNCS([calloc malloc realloc free])
AC_CHECK_FUNCS([perror printf fprintf])
AC_CHECK_FUNCS([fopen fgetc])
AC_CHECK_FUNCS([atoi])
AC_CHECK_FUNCS([memcmp memset])
AC_CHECK_FUNCS([setlocale mbstowcs wcsncpy wcstombs])
AC_CHECK_FUNCS([getopt])
AC_CHECK_FUNCS([signal])

dnl Check for libraries
AC_CHECK_LIB(m, pow, [], AC_MSG_ERROR([math library required]))

AC_CHECK_LIB(pthread, pthread_create, [], AC_MSG_ERROR([POSIX threads library required]))
AC_CHECK_HEADERS(pthread.h, [], AC_MSG_ERROR([POSIX threads headers required]))

AC_CHECK_LIB(crypto, EVP_get_cipherbyname, [], AC_MSG_ERROR([OpenSSL libraries required]))
AC_CHECK_HEADERS([openssl/ec.h openssl/evp.h openssl/obj_mac.h], [], AC_MSG_ERROR([OpenSSL headers required]))

AC_CHECK_LIB(db, db_create, [], AC_MSG_ERROR([BerkeleyDB library required]))
AC_CHECK_HEADERS(db.h, [], AC_MSG_ERROR([BerkeleyDB headers required]))

AC_CONFIG_FILES(Makefile)
AC_OUTPUT
