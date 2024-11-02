// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@solady/utils/SafeTransferLib.sol";

contract IDOTokenPlatform is ReentrancyGuard, Ownable {
    // Custom Errors
    error InvalidTokenAddress();
    error InvalidTokenPrice();
    error InvalidMinGoal();
    error MaxCapTooLow();
    error InvalidDuration();
    error IDONotExist();
    error IDONotStarted();
    error IDOEnded();
    error ExceedsMaxCap();
    error IDONotEnded();
    error MinGoalNotReached();
    error MinGoalReached();
    error AlreadyClaimed();
    error NoContribution();
    error TransferFailed();
    error TokenTransferFailed();
    error InsufficientTokenBalance();

    // events
    event IDOCreated(uint256 indexed idoId, address indexed token, uint256 tokenPrice, uint256 minGoal, uint256 maxCap);
    event Contributed(uint256 indexed idoId, address indexed user, uint256 amount);
    event TokensClaimed(uint256 indexed idoId, address indexed user, uint256 amount);
    event RefundClaimed(uint256 indexed idoId, address indexed user, uint256 amount);
    event FundsClaimed(uint256 indexed idoId, address indexed owner, uint256 amount);

    // IDO info
    struct IDOInfo {
        IERC20 token; // presale token
        uint256 tokenPrice; // token price (in wei)
        uint256 minGoal; // min goal (in wei)
        uint256 maxCap; // max cap (in wei)
        uint256 startTime; // start time
        uint256 endTime; // end time
        uint256 totalRaised; // total raised (in wei)
        uint8 decimals; // token decimals
        bool claimed; // project owner claimed or not
        bool exists; // IDO exists or not
    }

    // user info
    struct UserInfo {
        uint256 contribution; // user contribution (in wei)
        bool claimed; // user claimed or not
    }

    // IDO ID => IDO info
    mapping(uint256 => IDOInfo) public idoInfo;
    // IDO ID => user address => user info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // current IDO ID
    uint256 public currentIDOId;

    // constructor
    constructor() Ownable(msg.sender) { }

    // create IDO
    function createIDO(
        address _token,
        uint256 _tokenPrice,
        uint8 _tokenDecimals,
        uint256 _minGoal,
        uint256 _maxCap,
        uint256 _duration
    )
        external
        onlyOwner
    {
        if (_token == address(0)) revert InvalidTokenAddress();
        if (_tokenPrice == 0) revert InvalidTokenPrice();
        if (_minGoal == 0) revert InvalidMinGoal();
        if (_maxCap < _minGoal) revert MaxCapTooLow();
        if (_duration == 0) revert InvalidDuration();

        // check if the platform has enough tokens
        uint256 requiredTokens = (_maxCap * (10 ** _tokenDecimals)) / _tokenPrice;
        if (IERC20(_token).balanceOf(address(this)) < requiredTokens) {
            revert InsufficientTokenBalance();
        }

        // increment current IDO ID
        currentIDOId++;

        // create IDO info
        idoInfo[currentIDOId] = IDOInfo({
            token: IERC20(_token),
            tokenPrice: _tokenPrice,
            minGoal: _minGoal,
            maxCap: _maxCap,
            startTime: block.timestamp,
            endTime: block.timestamp + _duration,
            totalRaised: 0,
            decimals: _tokenDecimals,
            claimed: false,
            exists: true
        });

        // emit IDO created event
        emit IDOCreated(currentIDOId, _token, _tokenPrice, _minGoal, _maxCap);
    }

    // contribute to IDO via ETH
    function contribute(uint256 _idoId) external payable nonReentrant {
        IDOInfo storage ido = idoInfo[_idoId];
        if (!ido.exists) revert IDONotExist();

        // check if the IDO has started
        if (block.timestamp < ido.startTime) revert IDONotStarted();
        // check if the IDO has ended
        if (block.timestamp > ido.endTime) revert IDOEnded();
        // check if the total raised exceeds the max cap
        if (ido.totalRaised + msg.value > ido.maxCap) revert ExceedsMaxCap();

        // update user contribution
        userInfo[_idoId][msg.sender].contribution += msg.value;
        // update total raised
        ido.totalRaised += msg.value;

        // emit contributed event
        emit Contributed(_idoId, msg.sender, msg.value);
    }

    // claim tokens
    function claimTokens(uint256 _idoId) external nonReentrant {
        IDOInfo storage ido = idoInfo[_idoId];
        UserInfo storage user = userInfo[_idoId][msg.sender];
        if (!ido.exists) revert IDONotExist();

        // check if the IDO has ended
        if (block.timestamp <= ido.endTime) revert IDONotEnded();
        // check if the min goal is reached
        if (ido.totalRaised < ido.minGoal) revert MinGoalNotReached();
        // check if the user has claimed
        if (user.claimed) revert AlreadyClaimed();
        // check if the user has contributed
        if (user.contribution == 0) revert NoContribution();

        // calculate token amount
        uint256 tokenAmount = (user.contribution * (10 ** ido.decimals)) / ido.tokenPrice;
        // transfer tokens to user
        SafeTransferLib.safeTransfer(address(ido.token), msg.sender, tokenAmount);

        // mark user as claimed
        user.claimed = true;

        // emit tokens claimed event
        emit TokensClaimed(_idoId, msg.sender, tokenAmount);
    }

    // refound only if min goal is not reached
    function claimRefund(uint256 _idoId) external nonReentrant {
        IDOInfo storage ido = idoInfo[_idoId];
        UserInfo storage user = userInfo[_idoId][msg.sender];

        if (!ido.exists) revert IDONotExist();

        // check if the IDO has ended
        if (block.timestamp <= ido.endTime) revert IDONotEnded();
        // check if the min goal is reached
        if (ido.totalRaised >= ido.minGoal) revert MinGoalReached();
        // check if the user has claimed
        if (user.claimed) revert AlreadyClaimed();
        // check if the user has contributed
        if (user.contribution == 0) revert NoContribution();

        // calculate refund amount
        uint256 refundAmount = user.contribution;

        // transfer ETH to user
        (bool success,) = payable(msg.sender).call{ value: refundAmount }("");
        if (!success) revert TransferFailed();

        // mark user as claimed
        user.claimed = true;

        // emit refund claimed event
        emit RefundClaimed(_idoId, msg.sender, refundAmount);
    }

    // claim funds
    function claimFunds(uint256 _idoId) external onlyOwner nonReentrant {
        IDOInfo storage ido = idoInfo[_idoId];

        if (!ido.exists) revert IDONotExist();

        // check if the IDO has ended
        if (block.timestamp <= ido.endTime) revert IDONotEnded();
        // check if the min goal is reached
        if (ido.totalRaised < ido.minGoal) revert MinGoalNotReached();
        // check if the project owner has claimed
        if (ido.claimed) revert AlreadyClaimed();

        // calculate amount to transfer
        uint256 amountToTransfer = ido.totalRaised;

        // transfer ETH to project owner
        (bool success,) = payable(owner()).call{ value: amountToTransfer }("");
        if (!success) revert TransferFailed();

        // mark IDO as claimed
        ido.claimed = true;

        // emit funds claimed event
        emit FundsClaimed(_idoId, owner(), amountToTransfer);
    }

    // get IDO info
    function getIDOInfo(uint256 _idoId)
        external
        view
        returns (
            IERC20 token,
            uint256 tokenPrice,
            uint256 minGoal,
            uint256 maxCap,
            uint256 startTime,
            uint256 endTime,
            uint256 totalRaised,
            bool claimed,
            bool exists
        )
    {
        IDOInfo memory ido = idoInfo[_idoId];
        return (
            ido.token,
            ido.tokenPrice,
            ido.minGoal,
            ido.maxCap,
            ido.startTime,
            ido.endTime,
            ido.totalRaised,
            ido.claimed,
            ido.exists
        );
    }

    // get user info
    function getUserInfo(uint256 _idoId, address _user) external view returns (uint256 contribution, bool claimed) {
        UserInfo memory user = userInfo[_idoId][_user];
        return (user.contribution, user.claimed);
    }
}
