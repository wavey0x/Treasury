import pytest
from brownie import Contract
from brownie import accounts, config, network, project, web3



@pytest.fixture
def gov(accounts):
    addr = "0xC0E2830724C946a6748dDFE09753613cd38f6767"
    accounts[0].transfer(addr, 2e18)
    yield accounts.at(addr, force=True)

@pytest.fixture
def manager(accounts):
    yield accounts.at("0x72a34AbafAB09b15E7191822A679f28E067C4a16", force=True)


@pytest.fixture
def treasury(accounts, BeetsTreasury, gov, manager):
    treasury = gov.deploy(
        BeetsTreasury, manager)
    yield treasury
