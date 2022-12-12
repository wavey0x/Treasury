pragma solidity ^0.8.6;
pragma experimental ABIEncoderV2;

import {SafeERC20, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface ITradeFactory {
    function enable(address, address) external;
    function disable(address, address) external;
}

contract Treasury is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    event RetrieveToken (address token,uint amount);
    event RetrieveETH (uint amount);
    event PendingGovernance (address newPendingGov);
    event AcceptedGovernance (address newGov);
    event FailedETHSend(bytes returnedData);
    event ApprovedManager(address manager);
    event RemovedManager(address manager);

    address constant TARGET_TOKEN = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant TREASURY = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
    address public governance;
    address public pendingGovernance;
    address public tradeFactory;
    EnumerableSet.AddressSet private tokenList;
    EnumerableSet.AddressSet private managers;

    receive() external payable {}

    constructor() {
        governance = msg.sender;
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyTreasuryManagers {
        require(
            isManager(msg.sender) ||
            msg.sender == governance, "!Manager" 
        );
        _;
    }

    function setGovernance(address _newGov) external onlyGovernance {
        require(_newGov != address(0));
        pendingGovernance = _newGov;
        emit PendingGovernance(_newGov);
    }

    function acceptGovernance() external{
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = pendingGovernance;
        pendingGovernance = address(0);
        emit AcceptedGovernance(governance);
    }

    function sendToTargetTokenToTreasury() external onlyTreasuryManagers {
        uint amount = IERC20(TARGET_TOKEN).balanceOf(address(this));
        IERC20(TARGET_TOKEN).safeTransfer(TREASURY, amount);
    }

    function sendTokenToTreasury(address _token) external onlyTreasuryManagers {
        uint amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(TREASURY, amount);
    }

    function retrieveToken(address _token) external onlyGovernance {
        retrieveTokenExact(_token, IERC20(_token).balanceOf(address(this)));
    }

    function retrieveTokenExact(address _token, uint _amount) public onlyGovernance {
        IERC20(_token).safeTransfer(governance, _amount);
        emit RetrieveToken(_token, _amount);
    }

    function retrieveETH() external onlyGovernance {
        retrieveETHExact(address(this).balance);
    }

    function retrieveETHExact(uint _amount) public onlyGovernance nonReentrant {
        (bool success, bytes memory returnData) = governance.call{value: _amount}("");
        if(!success) {emit FailedETHSend(returnData);}
        require(success, "Sending ETH failed");
        emit RetrieveETH(_amount);
    }

    // ----------------- MANAGERS FUNCTIONS ---------------------
    function addManager(address _manager) external onlyGovernance{
        if (managers.add(_manager)) emit ApprovedManager(_manager);
    }

    /// @notice Allow owner to remove address from blacklist
    function removeManager(address _manager) external onlyGovernance {
        if (managers.remove(_manager)) emit RemovedManager(_manager);
    }

    /// @notice Check if address is approved to call split
    function isManager(address _manager) public view returns (bool) {
        return managers.contains(_manager);
    }

    /// @dev Helper function, if possible, avoid using on-chain as list can grow unbounded
    function getManagers() public view returns (address[] memory _callers) {
        address[] memory _managers = new address[](managers.length());
        for (uint i; i < managers.length(); i++) {
            _managers[i] = managers.at(i);
        }
    }

    // ----------------- YSWAPS FUNCTIONS ---------------------

    function setTradeFactory(address _tradeFactory, address[] calldata _tokens) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions(true);
        }
        tradeFactory = _tradeFactory;
        ITradeFactory tf = ITradeFactory(_tradeFactory);
        uint length = _tokens.length;
        for(uint i=0; i < length; i++){
            IERC20 token = IERC20(_tokens[i]);
            token.safeApprove(tradeFactory, type(uint).max);
            tf.enable(_tokens[i], TARGET_TOKEN);
        }
    }

    function approveTokenForTradeFactory(address _token) external onlyGovernance {
        if(!isOnTokenList(_token) && tokenList.add(_token)){
            IERC20(_token).safeApprove(tradeFactory, type(uint).max);
            ITradeFactory(tradeFactory).enable(_token, TARGET_TOKEN);
        }
    }

    /// @notice Remove permissions from tradefactory
    /// @param _disableTf Specify whether also disable TF. Option is given in case we need to bypass a reverting disable.
    function removeTradeFactoryPermissions(bool _disableTf) external onlyTreasuryManagers {
        _removeTradeFactoryPermissions(_disableTf);
    }

    function _removeTradeFactoryPermissions(bool _disableTf) internal {
        tradeFactory = address(0);
        uint length = tokenList.length();
        for (uint i; i < length; i++) {
            address token = tokenList.at(i);
            IERC20(token).safeApprove(tradeFactory, 0);
            if (_disableTf) ITradeFactory(tradeFactory).disable(token, TARGET_TOKEN);
        }
        delete tokenList;
    }

    function isOnTokenList(address _token) internal view returns (bool) {
        return tokenList.contains(_token);
    }

    function getTokenList() public view returns (address[] memory _tokenList) {
        _tokenList = new address[](tokenList.length());
        for (uint i; i < tokenList.length(); i++) {
            _tokenList[i] = tokenList.at(i);
        }
    }
}