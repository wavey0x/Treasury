import pytest
from brownie import Contract
from brownie import accounts, config, network, project, web3


@pytest.fixture
def token1():
    token_address = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599"  # WBTC
    yield Contract(token_address)

@pytest.fixture
def token2():
    token_address = "0x6B175474E89094C44Da98b954EedeAC495271d0F"  # DAI
    yield Contract(token_address)


@pytest.fixture
def gov(accounts):
    yield accounts.at("0xC0E2830724C946a6748dDFE09753613cd38f6767", force=True)

@pytest.fixture
def dev(accounts):
    yield accounts.at("0x441112Bd62b49371C2f876ee0740246f78B4111c", force=True)

@pytest.fixture
def whale(accounts, token1, token2):
    wbtc_whale = accounts.at("0xE78388b4CE79068e89Bf8aA7f218eF6b9AB0e9d0", force=True)
    dai_whale = accounts.at("0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503", force=True)
    token1.transfer(dai_whale, token1.balanceOf(wbtc_whale),{'from':wbtc_whale})
    yield dai_whale

@pytest.fixture
def treasury(accounts, Treasury, token1, gov, token2):
    treasury = gov.deploy(
        Treasury
    )
    yield treasury

