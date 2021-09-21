import pytest
import brownie
from brownie import Wei, accounts, Contract, config

def test_token_retrieve(treasury, token1, token2, gov, whale, chain):
    token1.transfer(treasury, 1e10,{'from': whale})
    token2.transfer(treasury, 1e20,{'from': whale})
    
    before_bal_1 = token1.balanceOf(gov)
    before_bal_2 = token2.balanceOf(gov)

    treasury.retrieveToken(token1,{"from": gov})
    treasury.retrieveToken(token2,{"from": gov})

    after_bal_1 = token1.balanceOf(gov)
    after_bal_2 = token2.balanceOf(gov)

    assert token1.balanceOf(treasury) == 0
    assert token2.balanceOf(treasury) == 0
    assert after_bal_1 > before_bal_1
    assert after_bal_2 > before_bal_2

    print(after_bal_1 / 1e8 , before_bal_1 / 1e8)
    print(after_bal_2 / 1e18 , before_bal_2 / 1e18)

    accounts[0].transfer(treasury, 1e18)
    assert treasury.balance() > 0
    treasury.retrieveETH({"from": gov})
    assert treasury.balance() == 0

    accounts[0].transfer(treasury, 2e18)
    bal_before = treasury.balance()
    assert treasury.balance() > 0
    treasury.retrieveETHExact(1e18, {"from": gov})
    assert treasury.balance() == bal_before - 1e18

def test_access_control(treasury, token1, token2, dev, gov, whale, accounts, chain):
    token1.transfer(treasury, 1e10,{'from': whale})
    token2.transfer(treasury, 1e20,{'from': whale})

    with brownie.reverts():
        treasury.retrieveToken(token1, {"from": dev})
    
    with brownie.reverts():
        treasury.retrieveTokenExact(token2, 1e18, {"from": dev})
    
    with brownie.reverts():
        treasury.setGovernance(gov, {"from": dev})

    with brownie.reverts():
        treasury.retrieveETH({"from": dev})
    
    with brownie.reverts():
        treasury.retrieveETHExact(1e18, {"from": dev})

    treasury.setGovernance(dev, {"from": gov})

    assert treasury.governance() == gov
    assert treasury.acceptGovernance({"from": dev})
    assert treasury.governance() == dev

    assert False