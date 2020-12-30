# Recovering Private Keys from the Bitcoin Blockchain

## The Plot

1. Download the BTC Blockchain
2. Parse blockchain into a relational database indexed by signature parameter `r`
3. Find occurances of duplicate `r` and return the transaction hash
4. Query the blockchain for the transactions, extract all relevant signature parameter (including pubkey, r, ..)
5. Use this project to recover the Private key
6. Win.

### 1) Download the BTC Blockchain

This is probably the easiest step. Run bitcoind in transaction preserving mode. Wait for it to fully sync.

`./bin/bitcoind --daemon --server --rpcuser=lala --rpcpassword=lolo -txindex=1 -printtoconsole #(--rescan)`

### 2) Parse the blockchain for transaction Data

Both the RPC interface and Python itself are way to slow to parse the excessive amount of transaction data available with the BTC blockchain. Modern languages like `golang` or `rust` are way faster for this purpose. With [rusty-blockparser](https://github.com/gcarq/rusty-blockparser) there's already an easy to adapt solution available. Here's a quick patch to rusty-blockparser that only outputs what we need (saving precious disk space):

```diff
diff --git a/src/callbacks/csvdump.rs b/src/callbacks/csvdump.rs
index 2248a5e..a839eac 100644
--- a/src/callbacks/csvdump.rs
+++ b/src/callbacks/csvdump.rs
@@ -13,13 +13,15 @@ use blockchain::proto::block::Block;
 use blockchain::proto::Hashed;
 use blockchain::utils;
 
+use rustc_serialize::base64::{ToBase64,STANDARD};
+
 
 /// Dumps the whole blockchain into csv files
 pub struct CsvDump {
     // Each structure gets stored in a seperate csv file
     dump_folder:    PathBuf,
-    block_writer:   BufWriter<File>,
-    tx_writer:      BufWriter<File>,
+    //block_writer:   BufWriter<File>,
+    //tx_writer:      BufWriter<File>,
     txin_writer:    BufWriter<File>,
     txout_writer:   BufWriter<File>,
 
@@ -59,8 +61,8 @@ impl Callback for CsvDump {
             let cap = 4000000;
             let cb = CsvDump {
                 dump_folder:    PathBuf::from(dump_folder),
-                block_writer:   try!(CsvDump::create_writer(cap, dump_folder.join("blocks.csv.tmp"))),
-                tx_writer:      try!(CsvDump::create_writer(cap, dump_folder.join("transactions.csv.tmp"))),
+                //block_writer:   try!(CsvDump::create_writer(cap, dump_folder.join("blocks.csv.tmp"))),
+                //tx_writer:      try!(CsvDump::create_writer(cap, dump_folder.join("transactions.csv.tmp"))),
                 txin_writer:    try!(CsvDump::create_writer(cap, dump_folder.join("tx_in.csv.tmp"))),
                 txout_writer:   try!(CsvDump::create_writer(cap, dump_folder.join("tx_out.csv.tmp"))),
                 start_height: 0, end_height: 0, tx_count: 0, in_count: 0, out_count: 0
@@ -82,12 +84,12 @@ impl Callback for CsvDump {
 
     fn on_block(&mut self, block: Block, block_height: usize) {
         // serialize block
-        self.block_writer.write_all(block.as_csv(block_height).as_bytes()).unwrap();
+        //self.block_writer.write_all(block.as_csv(block_height).as_bytes()).unwrap();
 
         // serialize transaction
         let block_hash = utils::arr_to_hex_swapped(&block.header.hash);
         for tx in block.txs {
-            self.tx_writer.write_all(tx.as_csv(&block_hash).as_bytes()).unwrap();
+            //self.tx_writer.write_all(tx.as_csv(&block_hash).as_bytes()).unwrap();
             let txid_str = utils::arr_to_hex_swapped(&tx.hash);
 
             // serialize inputs
@@ -157,12 +159,15 @@ impl TxInput {
     #[inline]
     fn as_csv(&self, txid: &str) -> String {
         // (@txid, @hashPrevOut, indexPrevOut, scriptSig, sequence)
-        format!("{};{};{};{};{}\n",
+        //format!("{};{};{};{};{}\n",
+		format!("{};{}\n",
             &txid,
-            &utils::arr_to_hex_swapped(&self.outpoint.txid),
-            &self.outpoint.index,
-            &utils::arr_to_hex(&self.script_sig),
-            &self.seq_no)
+            //&utils::arr_to_hex_swapped(&self.outpoint.txid),
+            //&self.outpoint.index,
+            //&utils::arr_to_hex(&self.script_sig),
+            &self.script_sig.to_base64(STANDARD),
+			//&self.seq_no
+			)
     }
 }
 
@@ -170,11 +175,12 @@ impl EvaluatedTxOut {
     #[inline]
     fn as_csv(&self, txid: &str, index: usize) -> String {
         // (@txid, indexOut, value, @scriptPubKey, address)
-        format!("{};{};{};{};{}\n",
-            &txid,
-            &index,
-            &self.out.value,
-            &utils::arr_to_hex(&self.out.script_pubkey),
+        //format!("{};{};{};{};{}\n",
+        format!("{};\n",
+            //&txid,
+            //&index,
+            //&self.out.value,
+            //&utils::arr_to_hex(&self.out.script_pubkey),
             &self.script.address)
     }
 }

```

// ☕ coffee break! :) until rusty-blockparser finishes doing the hard work!

We are especially interested in `tx_in`. Running rusty-blockparser on our synced blockchain takes some time and results in a >110 GB csv file containing the `txid` hash and base4(`script_sig`). Thats all we need for now as ECDSA signatures are contained within the `script_sig` vm code.

### 2.1) Populate the Database to find signatures with reused nonces

//Note: see Lessons Learnt 3) for database selection and tweaks

rusty-blockparser created a big csv file with txhashes and scriptsigs. The masterplan is to parse this information, extract the signature parameters and feed them into the database. To save some space we only track the `txhash`, as well as signature parameters `r` and `s` in the database. Even though we do not have the pubkey at hand as it is not stored with the `script_sig` but with the spending part we likely have all the information we need to find duplicates. This phase is all about storing only what we need to find the minority of txhashes with a script_sig containing an ecdsa signature with a reused nonce `k`. Since we'll be storing lots of transactions in the database we should try to minimize storage needed per transaction.


`#> bitcrack.py import tx_in.csv.tmp`
see [bitcrack.py](bitcoin/bitcrack.py)


### 2.2) Find duplicate values of r and try to recover the private key from this potential nonce reuse

First we extend the `EcDsaSignature` object to fit our Bitcoin usecase. I've added a quick check that tidies upthe pubkey to not contain any signature headers and some utility functions to convert the ecdsa signature to bitcoin addresses or WIF.
```python
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
```

Run `bitcrack.py` in recovery mode to have it connect to the mysql db, query for duplicate values of r, iterate all the `dup_r` transactions to get all information necessary to perform the nonce reuse attack.

`#> bitcrack.py recover`

//TBD ** TO BE CONTINUED **



# Lessons Learnt

#### 1) bitcoind's rpc interfaces is slow as hell

Nothing to add here. Yes it was obvious but I tried it. It's slow as hell and only usable if you are quering for some transactions, not for masses :)

#### 2) rust

While I'm more team golang I'll definitely give rust a try when I find some time. Once compiled it was really fast parsing the blockchain data files and the installation was as easy as telling the package manager to do whats necessary build the project.

#### 3) Database selection

3.1) sqlite odysse

Out of curiousity I started with quering the bitcoind rpc interface and feeding data into a local sqlite database but that quickly began to be dragging down performance. Once surpassing the 2 Mio to 5 Mio entries barrier an insert would take multiple seconds on my workstation.
    
3.2) mysql odyssee

When I switched to mysql things got better. However my initial db design was too flawed. Choosing a fixed char field for `r` or hashes turned out to consume way too much disk space. Changing the field to binary fixed the space issue, but having an index on `r` (remember, we want to get fast results for dup searches on r) just crippled database performance. Besides other mysql performance tweaks, initially removing the index and only building it once the data has been fed into the db turned out to safe lots of time.

*table setup*

* InnoDB, with AUTOINCR id, binary fields for txhash and sigdata r,s

```sql
CREATE TABLE `scriptsig_deduped` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `r` binary(32) NOT NULL,
  `s` binary(32) NOT NULL,
  `tx` binary(32) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_scriptsig_deduped_r` (`r`)
) ENGINE=InnoDB AUTO_INCREMENT=0 DEFAULT CHARSET=latin1;

```

*view: find duplicate 'r'*

```sql
VIEW `bitcoin`.`duplicate_r` AS select `bitcoin`.`scriptsig`.`r` AS `r`,`bitcoin`.`scriptsig`.`s` AS `s`,`bitcoin`.`scriptsig`.`tx` AS `tx`,count(`bitcoin`.`scriptsig`.`r`) AS `c` from `bitcoin`.`scriptsig` group by `bitcoin`.`scriptsig`.`r` having (`c` > 1);
```

*mysqld tweaks*

```ini
[mysqld]
#...
max_allowed_packet = 8M
sort_buffer_size = 8M
net_buffer_length = 8K
read_buffer_size = 2M
read_rnd_buffer_size = 8M
myisam_sort_buffer_size = 32M
query_cache_limit = 2M

innodb_buffer_pool_size = 1900M
innodb_log_file_size = 5M
innodb_log_buffer_size = 8M
innodb_flush_log_at_trx_commit = 1
innodb_lock_wait_timeout = 50
```

*monitoring*

Mysql Workbench turned out to be good in tweaking query performance

#### 4) Bloom filter

//TBD
