electrum-cracker
===============

bruteforcer for the 12 word brainwallet system of electum

You need a local instance of bitcoin-abe running, in order to access the balance of any address quickly.
Once you have set this up, just run "python bruteforcer.py" and cross your fingers.

You might need to install some missing python libraries. Do this using apt-get or easy_install / pip.

Addresses, with a total received amount of > 0 are dumped into addresses.txt. You can monitor it using "touch addresses.txt && tail -f addresses.txt".
Also a private key is dumped into the file. Once you find an address which received > 0 you can get the private key, import it into your electrum client, and generate all other addresses / change addresses this guy is using. Thanks for Electrum for this nice feature *haha*

In case you want to run this system distributed over multiple computers, edit your abe.conf to accept connections from the global network device, and adjust the correct ip into the bruteforcer.py by replacing "localhost" with the appropriate ip address or host name.

