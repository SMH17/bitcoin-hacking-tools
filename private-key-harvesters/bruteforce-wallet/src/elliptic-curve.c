/*
Bruteforce a wallet file.

Copyright 2014 Guillaume LE VAILLANT

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <openssl/ec.h>
#include <openssl/obj_mac.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "elliptic-curve.h"


void regenerate_eckey(EC_KEY *eckey, BIGNUM *skey)
{
  BN_CTX *ctx;
  EC_POINT *pkey;
  const EC_GROUP *group;

  group = EC_KEY_get0_group(eckey);
  ctx = BN_CTX_new();
  pkey = EC_POINT_new(group);
  if((ctx == NULL) || (pkey == NULL))
    {
      fprintf(stderr, "Error: memory allocation failed.\n\n");
      exit(EXIT_FAILURE);
    }

  EC_POINT_mul(group, pkey, skey, NULL, NULL, ctx);
  EC_KEY_set_private_key(eckey, skey);
  EC_KEY_set_public_key(eckey, pkey);
  EC_POINT_free(pkey);
  BN_CTX_free(ctx);
}

int check_eckey(unsigned char *seckey, unsigned char *pubkey, unsigned int pubkey_len)
{
  EC_KEY *eckey;
  BIGNUM *bn;
  unsigned char *pkey, *p;
  unsigned int size;
  int ret;

  /* Regenerate the public key from the secret key. */
  eckey = EC_KEY_new_by_curve_name(NID_secp256k1);
  if(eckey == NULL)
    {
      fprintf(stderr, "Error: memory allocation failed.\n\n");
      exit(EXIT_FAILURE);
    }
  if(pubkey_len == 33)
    EC_KEY_set_conv_form(eckey, POINT_CONVERSION_COMPRESSED);
  bn = BN_bin2bn(seckey, 32, BN_new());
  if(bn == NULL)
    {
      fprintf(stderr, "Error: memory allocation failed.\n\n");
      exit(EXIT_FAILURE);
    }
  regenerate_eckey(eckey, bn);
  BN_clear_free(bn);

  /* Get the generated public key. */
  size = i2o_ECPublicKey(eckey, NULL);
  pkey = (unsigned char *) malloc(size);
  if(pkey == NULL)
    {
      fprintf(stderr, "Error: memory allocation failed.\n\n");
      exit(EXIT_FAILURE);
    }
  p = pkey;
  i2o_ECPublicKey(eckey, &p);
  EC_KEY_free(eckey);

  /* Compare the generated public key and the real public key. */
  if(memcmp(pkey, pubkey, pubkey_len) == 0)
    ret = 1;
  else
    ret = 0;

  free(pkey);
  return(ret);
}
