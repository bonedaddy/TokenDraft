from web3 import Web3, IPCProvider
import web3
import sys
import json
from getpass import getpass
from time import sleep

# Example command invocation
# python3.5 transactionReplay.py 0x.... 0x.... password123 transactions.txt contract_abi.json /home/a/.ethereum/geth.ipc

# test account password is password123 (account 6 on rinkeby)
if len(sys.argv) < 6:
    msg = "Usage\npython3.5 transactionReplay.py <token-contract-address> <eth-acct>> <transaction-file> <abi-json-file> <ipc-path>"
    print('Incorrect command invokation\n%s' % msg)
    exit()


tokenContractAddress = sys.argv[1]
ethereumAccountAddress = sys.argv[2]
fileName = sys.argv[3]
tokenContractAbiDefinition = sys.argv[4]
gethIpcPath = sys.argv[5]

print("To convert ether price to wei use https://etherconverter.online")
ethereumAccountPassword =  getpass("Enter your ethereum account password:")
newPrice = float(input("Enter the new token price in ether:"))

with open(tokenContractAbiDefinition, 'r') as abi_definition:
    abi = json.load(abi_definition)

web3ctl = Web3(IPCProvider(gethIpcPath))

tokenContractHandler = web3ctl.eth.contract(abi, tokenContractAddress)

web3ctl.personal.unlockAccount(ethereumAccountAddress, ethereumAccountPassword)

newTokenPrice = Web3.toWei(newPrice, 'ether')
tokenContractHandler.transact({'from': ethereumAccountAddress}).updateTokenCost(newTokenPrice)