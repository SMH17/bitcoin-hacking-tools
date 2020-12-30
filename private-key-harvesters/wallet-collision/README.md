# wallet-collision
bitcoin/ethereum wallet collision
 (support Python3.4+)

## Feature
- support brute-force & dictionary attack
- multi-threading
- dual output, effective wallet & wallet with balance

## Dependency
Bitcoin:
- requests
- bit

Ethereum:
- requests
- ecdsa
- pysha3

## How to use it?
Warning: To bypass blockchain.info/etherchain.org API request limit, please request an API key

### Brute-force attack
`python wallet.py`, run with your luck.

It will auto-generate random number as private key.

### Dictionary attack
Replace `dict.txt` with your password dictionary file.

`python weak.py`, run with your dictionary.

It will use your passphrase as private key.

## Where is the result?
The output file `found.txt` contains information about effective wallet.

The output file `fund.txt` contains information about wallet with balance.

Here is different information instruction.

### Bitcoin
column 1: `0: Address, 1: Compressed Address`

column 2: balance

column 3: total sent balance

column 4: private key

column 5: address

### Ethereum
column 1: balance

column 2: private key

column 3: address

## License
wallet-collision is published under Apache License 2.0 License. See the LICENSE file for more.
