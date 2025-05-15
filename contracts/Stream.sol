// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IStream} from "./interfaces/IStream.sol";
import {Struct} from "./libraries/Struct.sol";
import {CreateLogic} from "./libraries/CreateLogic.sol";
import {WithdrawLogic} from "./libraries/WithdrawLogic.sol";
import {ExtendLogic} from "./libraries/ExtendLogic.sol";

contract Stream is 
    IStream, 
    Initializable,
    ReentrancyGuardUpgradeable, 
    Ownable2StepUpgradeable, 
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    /*** Storage Properties ***/
    address public WETH;
    address public GATEWAY;

    /**
     * @notice Counter for new stream ids.
     */
    uint256 public nextStreamId;

    address private _feeRecipient;
    address private _autoWithdrawAccount;
    uint256 private _autoWithdrawFeeForOnce;

    address[] private _tokenlist;
    mapping(address => bool) private _tokenAllowed;
    mapping(address => uint256) private _tokenFeeRate;

    /**
     * @notice The stream objects identifiable by their unsigned integer ids.
     */
    mapping(uint256 => Struct.Stream) private _streams;

    /*** Modifiers ***/

    /**
     * @dev Throws if the provided id does not point to a valid stream.
     */
    modifier streamExists(uint256 streamId) {
        require(_streams[streamId].isEntity, "stream does not exist");
        _;
    }

    /*** Events ***/

    /**
     * @notice Emits when a stream is successfully closed and tokens are transferred back on a pro rata basis.
     */
    event CloseStream(uint256 indexed streamId, address indexed operator, uint256 senderBalance, uint256 recipientBalance);

    /**
     * @notice Emits when a stream is successfully paused.
     */
    event PauseStream(uint256 indexed streamId, address indexed operator, uint256 recipientBalance);

    /**
     * @notice Emits when a stream is successfully resumed.
     */
    event ResumeStream(uint256 indexed streamId, address indexed operator, uint256 duration);

    /**
     * @notice Emits when the recipient of a stream is successfully changed.
     */
    event SetNewRecipient(uint256 indexed streamId, address indexed operator, address indexed newRecipient);

    /**
     * @notice Emits when a token is successfully registered.
     */
    event TokenRegister(address indexed tokenAddress, uint256 feeRate);

    /**
     * @notice Emits when a token is successfully unregistered.
     */
    event TokenUnRegister(address indexed tokenAddress);

    /*** Contract Logic Starts Here */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address weth_,
        address feeRecipient_,
        address autoWithdrawAccount_,
        uint256 autoWithdrawFeeForOnce_
    ) initializer public {
        __Ownable2Step_init();
        transferOwnership(owner_);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        WETH = weth_;
        _feeRecipient = feeRecipient_;
        _autoWithdrawAccount = autoWithdrawAccount_;
        _autoWithdrawFeeForOnce = autoWithdrawFeeForOnce_;
        nextStreamId = 100000;
        tokenRegister(WETH, 25);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /*** View Functions ***/
    function tokenFeeRate(address tokenAddress) external view override returns (uint256) {
        require(_tokenAllowed[tokenAddress], "token not registered");
        return _tokenFeeRate[tokenAddress];
    }

    function autoWithdrawFeeForOnce() external view override returns (uint256) {
        return _autoWithdrawFeeForOnce;
    }

    function autoWithdrawAccount() external view override returns (address) {
        return _autoWithdrawAccount;
    }

    function feeRecipient() external view override returns (address) {
        return _feeRecipient;
    }

    /**
     * @notice Returns the stream with all its properties.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream to query.
     */
    function getStream(uint256 streamId)
        external
        view
        override
        streamExists(streamId)
        returns (Struct.Stream memory)
    {
        return _streams[streamId];
    }

    /**
     * @notice Returns either the delta in intervals between `block.timestamp` and `startTime` or
     *  between `stopTime` and `startTime, whichever is smaller. If `block.timestamp` is before
     *  `startTime`, it returns 0.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream for which to query the delta.
     * @return delta The time delta in intervals.
     */
    function deltaOf(uint256 streamId) public view streamExists(streamId) returns (uint256 delta) {
        Struct.Stream memory stream = _streams[streamId];
        if (block.timestamp < stream.lastWithdrawTime + stream.pauseInfo.accPauseTime) {
            return 0;
        }

        if (block.timestamp > stream.stopTime) {
            return (stream.stopTime - stream.lastWithdrawTime - stream.pauseInfo.accPauseTime) / stream.interval;
        } else {
            return (block.timestamp - stream.lastWithdrawTime - stream.pauseInfo.accPauseTime) / stream.interval;
        }
    }

    /**
     * @notice Returns the available funds for the given stream id and address.
     * @dev Throws if the id does not point to a valid stream.
     * @param streamId The id of the stream for which to query the balance.
     * @param who The address for which to query the balance.
     * @return balance The total funds allocated to `who` as uint256.
     */
    function balanceOf(uint256 streamId, address who) public view override streamExists(streamId) returns (uint256 balance) {
        Struct.Stream memory stream = _streams[streamId];

        uint256 delta = deltaOf(streamId);
        uint256 recipientBalance = delta * stream.ratePerInterval;
        if (stream.cliffInfo.cliffDone == false && stream.cliffInfo.cliffTime <= block.timestamp) {
            recipientBalance += stream.cliffInfo.cliffAmount;
        }

        if (who == stream.recipient) {
            return recipientBalance;
        } else if (who == stream.sender) {
            uint256 senderBalance = stream.remainingBalance - recipientBalance;
            return senderBalance;
        }
        return 0;
    }

    /*** Public Effects & Interactions Functions ***/

    function batchCreateStream(Struct.CreateStreamParams[] calldata createParams) external payable nonReentrant {
        uint256 senderValue = msg.value;
        for (uint256 i = 0; i < createParams.length; i++) {
            require(_tokenAllowed[createParams[i].tokenAddress], "token not registered");

            uint256 autoWithdrawFee = CreateLogic.create(
                nextStreamId,
                senderValue,
                Struct.GlobalParams({
                    weth: WETH,
                    gateway: GATEWAY,
                    feeRecipient: _feeRecipient,
                    autoWithdrawAccount: _autoWithdrawAccount,
                    autoWithdrawFeeForOnce: _autoWithdrawFeeForOnce,
                    tokenFeeRate: _tokenFeeRate[createParams[i].tokenAddress]
                }),
                createParams[i], 
                _streams
            );

            senderValue -= autoWithdrawFee;

            /* Increment the next stream id. */
            nextStreamId = nextStreamId + 1;
        }

        /* reback the gas fee */
        payable(msg.sender).transfer(senderValue);
    }

    function createStream(
        Struct.CreateStreamParams calldata createParams
    )
        external 
        payable 
        override 
        nonReentrant
    {
        require(_tokenAllowed[createParams.tokenAddress], "token not registered");

        uint256 gasUsed = CreateLogic.create(
            nextStreamId,
            msg.value,
            Struct.GlobalParams({
                weth: WETH,
                gateway: GATEWAY,
                feeRecipient: _feeRecipient,
                autoWithdrawAccount: _autoWithdrawAccount,
                autoWithdrawFeeForOnce: _autoWithdrawFeeForOnce,
                tokenFeeRate: _tokenFeeRate[createParams.tokenAddress]
            }),
            createParams, 
            _streams
        );
        
        /* Increment the next stream id. */
        nextStreamId = nextStreamId + 1;

        /* reback the gas fee */
        payable(msg.sender).transfer(msg.value - gasUsed);
    }

    function batchExtendStream(uint256[] calldata streamIds, uint256[] calldata stopTime) external payable nonReentrant {
        uint256 senderValue = msg.value;
        require(streamIds.length == stopTime.length, "length not match");
        for (uint256 i = 0; i < streamIds.length; i++) {
            Struct.Stream storage stream = _streams[streamIds[i]];
            require(stream.isEntity, "stream does not exist");
            uint256 gasUsed = ExtendLogic.extend(
                streamIds[i],
                stopTime[i],
                senderValue,
                Struct.GlobalParams({
                    weth: WETH,
                    gateway: GATEWAY,
                    feeRecipient: _feeRecipient,
                    autoWithdrawAccount: _autoWithdrawAccount,
                    autoWithdrawFeeForOnce: _autoWithdrawFeeForOnce,
                    tokenFeeRate: _tokenFeeRate[stream.tokenAddress]
                }),
                stream
            );

            senderValue -= gasUsed;
        }

        /* reback the gas fee */
        payable(msg.sender).transfer(senderValue);
    }

    function extendStream(uint256 streamId, uint256 stopTime) 
        external 
        payable 
        override 
        nonReentrant 
        streamExists(streamId) 
    {
        Struct.Stream storage stream = _streams[streamId];

        uint256 gasUsed = ExtendLogic.extend(
            streamId,
            stopTime,
            msg.value,
            Struct.GlobalParams({
                weth: WETH,
                gateway: GATEWAY,
                feeRecipient: _feeRecipient,
                autoWithdrawAccount: _autoWithdrawAccount,
                autoWithdrawFeeForOnce: _autoWithdrawFeeForOnce,
                tokenFeeRate: _tokenFeeRate[stream.tokenAddress]
            }),
            stream
        );

        /* reback the gas fee */
        payable(msg.sender).transfer(msg.value - gasUsed);
    }

    function batchWithdrawFromStream(uint256[] calldata streamIds) external {
        for (uint256 i = 0; i < streamIds.length; i++) {
            withdrawFromStream(streamIds[i]);
        }
    }

    /**
     * @notice Withdraws from the contract to the recipient's account.
     * @param streamId The id of the stream to withdraw tokens from.
     */
    function withdrawFromStream(uint256 streamId)
        public
        override
        nonReentrant
        streamExists(streamId)
    {
        Struct.Stream storage stream = _streams[streamId];

        uint256 delta = deltaOf(streamId);
        uint256 balance = balanceOf(streamId, stream.recipient);

        require(balance > 0, "no balance to withdraw");

        WithdrawLogic.withdraw(
            streamId,
            delta,
            balance,
            Struct.GlobalParams({
                weth: WETH,
                gateway: GATEWAY,
                feeRecipient: _feeRecipient,
                autoWithdrawAccount: _autoWithdrawAccount,
                autoWithdrawFeeForOnce: _autoWithdrawFeeForOnce,
                tokenFeeRate: _tokenFeeRate[stream.tokenAddress]
            }),
            stream
        );
    }

    function batchCloseStream(uint256[] calldata streamIds) external {
        for (uint256 i = 0; i < streamIds.length; i++) {
            closeStream(streamIds[i]);
        }
    }

    /**
     * @notice close the stream and transfers the tokens back on a pro rata basis.
     * @dev Throws if the id does not point to a valid stream.
     *  Throws if the caller is not the sender or the recipient of the stream.
     *  Throws if there is a token transfer failure.
     * @param streamId The id of the stream to close.
     */
    function closeStream(uint256 streamId) 
        public 
        override 
        nonReentrant
        streamExists(streamId) 
    {
        Struct.Stream storage stream = _streams[streamId];
        require(stream.closed == false, "stream is closed");

        if (stream.pauseInfo.isPaused == true) {
            /* resume the stream */
            _resumeStream(streamId, stream);
        }

        uint256 delta = deltaOf(streamId);
        uint256 senderBalance = balanceOf(streamId, stream.sender);
        uint256 recipientBalance = balanceOf(streamId, stream.recipient);

        if (WETH == stream.tokenAddress && msg.sender == stream.onBehalfOf) {
            if (tx.origin == stream.sender) {
                require(
                    stream.featureInfo.closeable == Struct.Capability.Both || 
                    stream.featureInfo.closeable == Struct.Capability.Sender, 
                    "sender is not allowed to close the stream");
            } else if (tx.origin == stream.recipient) {
                require(
                    stream.featureInfo.closeable == Struct.Capability.Both || 
                    stream.featureInfo.closeable == Struct.Capability.Recipient, 
                    "recipient is not allowed to close the stream");
            } else {
                revert("not allowed to close the stream");
            }

            IERC20(stream.tokenAddress).safeTransfer(stream.onBehalfOf, _streams[streamId].remainingBalance);
        } else {
            if (msg.sender == stream.sender) {
                require(
                    stream.featureInfo.closeable == Struct.Capability.Both || 
                    stream.featureInfo.closeable == Struct.Capability.Sender, 
                    "sender is not allowed to close the stream");
            } else if (msg.sender == stream.recipient) {
                require(
                    stream.featureInfo.closeable == Struct.Capability.Both || 
                    stream.featureInfo.closeable == Struct.Capability.Recipient, 
                    "recipient is not allowed to close the stream");
            } else {
                revert("not allowed to close the stream");
            }

            if (recipientBalance > 0) {
                uint256 recipientBalanceFee = recipientBalance * _tokenFeeRate[stream.tokenAddress] / 10000;
                IERC20(stream.tokenAddress).safeTransfer(_feeRecipient, recipientBalanceFee);
                IERC20(stream.tokenAddress).safeTransfer(stream.recipient, recipientBalance - recipientBalanceFee);
            }
            if (senderBalance > 0) {
                IERC20(stream.tokenAddress).safeTransfer(stream.sender, senderBalance);
            }
        }

        /* send cliff */
        if (stream.cliffInfo.cliffDone == false) {
            stream.cliffInfo.cliffDone = true;
        }

        if (delta > 0) {
            stream.lastWithdrawTime += stream.interval * delta + stream.pauseInfo.accPauseTime;
            stream.pauseInfo.accPauseTime = 0;
        }

        stream.closed = true;
        stream.remainingBalance = 0;

        emit CloseStream(streamId, msg.sender, senderBalance, recipientBalance);
    }

    function batchPauseStream(uint256[] calldata streamIds) external {
        for (uint256 i = 0; i < streamIds.length; i++) {
            pauseStream(streamIds[i]);
        }
    }

    function pauseStream(uint256 streamId) public override nonReentrant streamExists(streamId) {
        Struct.Stream storage stream = _streams[streamId];
        /* check the status of this stream */
        require(stream.pauseInfo.isPaused == false, "stream is paused");
        require(stream.closed == false, "stream is closed");
        require(stream.stopTime > block.timestamp, "stream is expired");

        /* check the permission */
        if (WETH == stream.tokenAddress && msg.sender == stream.onBehalfOf){
            
            if (tx.origin == stream.sender) {
                require(
                    stream.featureInfo.pauseable == Struct.Capability.Both || 
                    stream.featureInfo.pauseable == Struct.Capability.Sender, 
                    "sender is not allowed to pause the stream");
                stream.pauseInfo.pauseBy = stream.sender;
            } else if (tx.origin == stream.recipient) {
                require(
                    stream.featureInfo.pauseable == Struct.Capability.Both || 
                    stream.featureInfo.pauseable == Struct.Capability.Recipient, 
                    "recipient is not allowed to pause the stream");
                stream.pauseInfo.pauseBy = stream.recipient;
            } else {
                revert("not allowed to pause the stream");
            }
        } else {
            if (msg.sender == stream.sender) {
                require(
                    stream.featureInfo.pauseable == Struct.Capability.Both || 
                    stream.featureInfo.pauseable == Struct.Capability.Sender, 
                    "sender is not allowed to pause the stream");
                stream.pauseInfo.pauseBy = stream.sender;
            } else if (msg.sender == stream.recipient) {
                require(
                    stream.featureInfo.pauseable == Struct.Capability.Both || 
                    stream.featureInfo.pauseable == Struct.Capability.Recipient, 
                    "recipient is not allowed to pause the stream");
                stream.pauseInfo.pauseBy = stream.recipient;
            } else {
                revert("not allowed to pause the stream");
            }
        }

        /* withdraw the remaining balance */
        uint256 balance = balanceOf(streamId, stream.recipient);
        if (balance > 0) {
            WithdrawLogic.withdraw(
                streamId,
                deltaOf(streamId),
                balance,
                Struct.GlobalParams({
                    weth: WETH,
                    gateway: GATEWAY,
                    feeRecipient: _feeRecipient,
                    autoWithdrawAccount: _autoWithdrawAccount,
                    autoWithdrawFeeForOnce: _autoWithdrawFeeForOnce,
                    tokenFeeRate: _tokenFeeRate[stream.tokenAddress]
                }),
                stream
            );
        }

        /* pause the stream */
        stream.pauseInfo.pauseAt = block.timestamp;
        stream.pauseInfo.isPaused = true;

        /* emit event */
        emit PauseStream(streamId, stream.pauseInfo.pauseBy, balance);
    }

    function batchResumeStream(uint256[] calldata streamIds) external {
        for (uint256 i = 0; i < streamIds.length; i++) {
            resumeStream(streamIds[i]);
        }
    }

    function resumeStream(uint256 streamId) public override nonReentrant streamExists(streamId) {
        Struct.Stream storage stream = _streams[streamId];
        /* check the status of this stream */
        require(stream.pauseInfo.isPaused == true, "stream is not paused");
        require(stream.closed == false, "stream is closed");
        require(
            stream.pauseInfo.pauseBy == msg.sender || owner() == msg.sender,
            "only the one who paused the stream can resume it"
        );

        /* resume the stream */
        _resumeStream(streamId, stream);
    }

    function _resumeStream(uint256 streamId, Struct.Stream storage stream) internal {
        /* resume the stream */
        uint256 duration = 0;
        if (block.timestamp > stream.startTime) {
            if (stream.pauseInfo.pauseAt > stream.startTime) {
                duration = block.timestamp - stream.pauseInfo.pauseAt;
            } else {
                duration = block.timestamp - stream.startTime;
            }
        }

        stream.pauseInfo.isPaused = false;
        stream.pauseInfo.pauseAt = 0;
        stream.pauseInfo.pauseBy = address(0x00);
        stream.pauseInfo.accPauseTime += duration;
        stream.stopTime += duration;

        /* emit event */
        emit ResumeStream(streamId, msg.sender, duration);
    }

    function batchSetNewRecipient(uint256[] calldata streamIds, address[] calldata newRecipient) external {
        require(streamIds.length == newRecipient.length, "length not match");

        for (uint256 i = 0; i < streamIds.length; i++) {
            setNewRecipient(streamIds[i], newRecipient[i]);
        }
    }

    function setNewRecipient(uint256 streamId, address newRecipient) public override streamExists(streamId) {
        Struct.Stream storage stream = _streams[streamId];
        require(stream.closed == false, "stream is closed");
        require(stream.pauseInfo.isPaused == false, "stream is paused");

        /* check the permission */
        if (msg.sender == stream.sender) {
            require(
                stream.featureInfo.recipientModifiable == Struct.Capability.Both || 
                stream.featureInfo.recipientModifiable == Struct.Capability.Sender, 
                "sender is not allowed to change the recipient");
        } else if (msg.sender == stream.recipient) {
            require(
                stream.featureInfo.recipientModifiable == Struct.Capability.Both || 
                stream.featureInfo.recipientModifiable == Struct.Capability.Recipient, 
                "recipient is not allowed to change the recipient");
        } else {
            revert("not allowed to change the recipient");
        }

        stream.recipient = newRecipient;

        /* emit event */
        emit SetNewRecipient(streamId, msg.sender, newRecipient);
    }

    function tokenlist() external view override returns (address[] memory) {
        return _tokenlist;
    }

    function tokenBalance(address[] calldata tokenAddresses) external view override returns (uint256[] memory) {
        uint256[] memory tvl = new uint256[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            address tokenAddress = tokenAddresses[i];
            tvl[i] = IERC20(tokenAddress).balanceOf(address(this));
        }
        return tvl;
    }

    function tokenRegister(address tokenAddress, uint256 feeRate) public onlyOwner {
        if (_tokenAllowed[tokenAddress]) {
            _tokenFeeRate[tokenAddress] = feeRate;
        } else {
            _tokenAllowed[tokenAddress] = true;
            _tokenFeeRate[tokenAddress] = feeRate;
            _tokenlist.push(tokenAddress);
        }

        /* emit event */
        emit TokenRegister(tokenAddress, feeRate);
    }

    function tokenUnRegister(address tokenAddress) public onlyOwner {
        require(_tokenAllowed[tokenAddress], "token not registered");
        require(tokenAddress != WETH, "cannot unregister WETH");
        
        _tokenAllowed[tokenAddress] = false;
        
        for (uint256 i = 0; i < _tokenlist.length; i++) {
            if (_tokenlist[i] == tokenAddress) {
                _tokenlist[i] = _tokenlist[_tokenlist.length - 1];
                _tokenlist.pop();
                break;
            }
        }
        
        delete _tokenFeeRate[tokenAddress];
        
        emit TokenUnRegister(tokenAddress);
    }
    

    function batchTokenRegister(address[] calldata tokenAddresses, uint256[] calldata feeRates) external onlyOwner {
        require(tokenAddresses.length == feeRates.length, "length not match");

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            tokenRegister(tokenAddresses[i], feeRates[i]);
        }
    }

    function batchTokenUnRegister(address[] calldata tokenAddresses) external onlyOwner {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            tokenUnRegister(tokenAddresses[i]);
        }
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        _feeRecipient = newFeeRecipient;
    }

    function setAutoWithdrawAccount(address newAutoWithdrawAccount) external onlyOwner {
        _autoWithdrawAccount = newAutoWithdrawAccount;
    }

    function setAutoWithdrawFee(uint256 newAutoWithdrawFee) external onlyOwner {
        _autoWithdrawFeeForOnce = newAutoWithdrawFee;
    }

    function setGateway(address gateway) external onlyOwner {
        GATEWAY = gateway;
    }
}