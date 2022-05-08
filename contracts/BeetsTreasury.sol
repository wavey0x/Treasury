pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import {SafeERC20, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IBalancerPool is IERC20 {
    function getPoolId() external view returns (bytes32 poolId);
}

interface IBalancerVault {
    enum JoinKind {INIT, EXACT_TOKENS_IN_FOR_BPT_OUT, TOKEN_IN_FOR_EXACT_BPT_OUT, ALL_TOKENS_IN_FOR_EXACT_BPT_OUT}
    enum ExitKind {EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, EXACT_BPT_IN_FOR_TOKENS_OUT, BPT_IN_FOR_EXACT_TOKENS_OUT}

    // enconding formats https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/balancer-js/src/pool-weighted/encoder.ts
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest calldata request
    ) external;
}

interface IVault is IERC20 {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;
}

interface IBeetsBar is IERC20 {
    function vestingToken() external view returns (address);

    function enter(uint256 _amount) external;

    function leave(uint256 _shareOfFreshBeets) external;

    function shareRevenue(uint256 _amount) external;
}


contract BeetsTreasury is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address;

    address public governance;
    address public manager;
    address public pendingGovernance;
    IBalancerVault public constant bVault = IBalancerVault(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    IBalancerPool public constant stakeLp = IBalancerPool(0xcdE5a11a4ACB4eE4c805352Cec57E236bdBC3837);
    IERC20 public constant beets = IERC20(0xF24Bcf4d1e507740041C9cFd2DddB29585aDCe1e);
    IERC20 public constant wftm = IERC20(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    IBeetsBar public constant fBeets = IBeetsBar(0xfcef8a994209d6916EB2C86cDD2AFD60Aa6F54b1);
    IVault public constant yvFBeets = IVault(0x1e2fe8074a5ce1Bb7394856B0C618E75D823B93b);
    address[] internal assets;
    uint256 public constant max = type(uint256).max;

    event RetrieveToken (address token, uint amount);
    event RetrieveETH (uint amount);
    event PendingGovernance (address newPendingGov);
    event AcceptedGovernance (address newGov);
    event FailedETHSend(bytes returnedData);

    receive() external payable {}

    constructor(address _manager) public {
        governance = msg.sender;
        manager = _manager;
        assets = [address(wftm), address(beets)];

        beets.approve(address(bVault), max);
        stakeLp.approve(address(fBeets), max);
        stakeLp.approve(address(bVault), max);
        fBeets.approve(address(yvFBeets), max);
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "!governance");
        _;
    }

    modifier onlyAllowed {
        require(msg.sender == governance || msg.sender == manager, "!allowed");
        _;
    }

    function setGovernance(address _newGov) external onlyGovernance {
        require(_newGov != address(0));
        pendingGovernance = _newGov;
        emit PendingGovernance(_newGov);
    }

    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "!pendingGovernance");
        governance = pendingGovernance;
        pendingGovernance = address(0);
        emit AcceptedGovernance(governance);
    }

    //Retrieve full balance of token in contract
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
        (bool success, bytes memory returnData) = governance.call{value : _amount}("");
        if (!success) {emit FailedETHSend(returnData);}
        require(success, "Sending ETH failed");
        emit RetrieveETH(_amount);
    }


    //  ====== BEETS HELPERS ======

    function lp(uint _amount, bool _join) external onlyAllowed {
        _lp(_amount, _join);
    }

    function _lp(uint _amount, bool _join) internal {
        if (_amount > 0) {
            uint256[] memory amounts = new uint256[](2);
            // wftm 0
            // beets 1
            if (_join) {
                amounts[1] = _amount;
                bytes memory userData = abi.encode(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, 0);
                IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(assets, amounts, userData, false);
                bVault.joinPool(stakeLp.getPoolId(), address(this), address(this), request);
            } else {
                bytes memory userData = abi.encode(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, _amount, 1);
                IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest(assets, amounts, userData, false);
                bVault.exitPool(stakeLp.getPoolId(), address(this), address(this), request);
            }

        }
    }

    function beetsBar(uint _bpts, bool _mint) external onlyAllowed {
        _beetsBar(_bpts, _mint);
    }

    function _beetsBar(uint _amount, bool _mint) internal {
        if (_amount > 0) {
            if (_mint) {
                // mint fbeets with lpTokens aka bpt
                fBeets.enter(_amount);
            } else {
                // burn fbeets
                fBeets.leave(_amount);
            }
        }
    }

    function yv(uint256 _amount, bool _deposit) external onlyAllowed {
        _yv(_amount, _deposit);
    }

    function _yv(uint256 _amount, bool _deposit) internal {
        if (_deposit) {
            yvFBeets.deposit(_amount);
        } else {
            yvFBeets.withdraw(_amount);
        }
    }

    function enterAll() external onlyAllowed {
        _lp(beets.balanceOf(address(this)), true);
        _beetsBar(stakeLp.balanceOf(address(this)), true);
        _yv(fBeets.balanceOf(address(this)), true);
    }

    function exitAll() external onlyAllowed {
        _yv(yvFBeets.balanceOf(address(this)), false);
        _beetsBar(fBeets.balanceOf(address(this)), false);
        _lp(stakeLp.balanceOf(address(this)), false);
    }

    function balances() external returns (uint256 _beets, uint256 _stakeLp, uint256 _fBeets, uint256 _yvFBeets){
        return (
        beets.balanceOf(address(this)),
        stakeLp.balanceOf(address(this)),
        fBeets.balanceOf(address(this)),
        yvFBeets.balanceOf(address(this)));
    }
}
