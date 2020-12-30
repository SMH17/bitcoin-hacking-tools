import threading
import os
import time
import random
import codecs
import requests
import json
from ecdsa import SigningKey, SECP256k1
import sha3
import traceback

maxPage = pow(2,256) / 128

def getRandPage():
    return random.randint(1, maxPage)

def getPage(pageNum):
    keyList = []
    addrList = []
    addrStr = ""
    num = (pageNum - 1) * 50 + 1
    try:
        for i in range(num, num + 50):
            key = hex(i)[2:]
            if len(key) < 64: key = "0"*(64-len(key)) + key
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
fp_found = open("found.txt", "w+")
fp_fund = open("fund.txt", "w+")

def getWallet():
    global getCount
    while True:
        page = getRandPage()
        pageRet = getPage(page)
        getCount = getCount + len(pageRet[1])

        try:
            balancesRet = getBalances(pageRet[2])
            for balance in balancesRet:
                key = ""
                for i in range(0, len(pageRet[1])):
                    if balance['address'] == pageRet[1][i]:
                        key = pageRet[0][i]
                        break
                if key == "": continue
                fp_found.write(str(balance['balance']) + " " + key + " " + balance['address'] + "\n")
                if balance['balance'] > 0:
                    fp_fund.write(str(balance['balance']) + " " + key + " " + balance['address'] + "\n")
                #print (balance['balance'], key, balance['address'])
            fp_found.flush()
            fp_fund.flush()
        except:
            traceback.print_exc()
            continue
        clearScreen()
        print (getCount)

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
