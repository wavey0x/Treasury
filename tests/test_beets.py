import pytest
import brownie
from brownie import Wei, accounts, Contract, config


def test_beets(treasury):
    ssbeets_dai = Contract("0x5583cB73e1831AF95787383B179467813A380b47")
    gov = accounts.at(Contract(ssbeets_dai.vault()).governance())
    ssbeets_dai.setKeepParams(treasury, 1000, {'from': gov})
    ssbeets_dai.harvest({'from': gov})

    yvFBeets = Contract(treasury.yvFBeets())
    yv_before = yvFBeets.balanceOf(treasury.address)
    sms = accounts.at(treasury.manager(), force=True)
    ssbeets_dai.harvest({'from': gov})
    treasury.enterAll({'from': sms})
    assert yvFBeets.balanceOf(treasury.address) > yv_before
