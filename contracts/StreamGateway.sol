// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IWETH} from './interfaces/IWETH.sol';
import {IStream} from "./interfaces/IStream.sol";
import {Struct} from "./libraries/Struct.sol";

contract StreamGateway is 
    Initializable,
    Ownable2StepUpgradeable, 
    ReentrancyGuardUpgradeable, 
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    IWETH public WETH;
    IStream public STREAM;

    /*** Contract Logic Starts Here */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address owner_,
        address weth,
        address stream
    ) initializer public {
        __Ownable2Step_init();
        transferOwnership(owner_);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        WETH = IWETH(weth);
        STREAM = IStream(stream);
        IWETH(weth).approve(address(stream), type(uint256).max);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    function batchCreateStreamETH(
        Struct.CreateStreamParams[] calldata inputParams
    ) external payable nonReentrant {
        uint256 totalDeposit = 0;
        uint256 totalAutoWithdrawFee = 0;
        uint256 autoWithdrawFeeForOnce = STREAM.autoWithdrawFeeForOnce();
        uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
        address feeRecipient = STREAM.feeRecipient();
        for (uint256 i = 0; i < inputParams.length; i++) {
            Struct.CreateStreamParams calldata params = inputParams[i];
            require(params.tokenAddress == address(0x00), "tokenAddress must be 0 address");
            uint256 autoWithdrawFee = 0;
            if (params.autoWithdraw) {
                autoWithdrawFee = autoWithdrawFeeForOnce * 
                    ((params.stopTime - params.startTime) / params.autoWithdrawInterval + 1);
                totalAutoWithdrawFee += autoWithdrawFee;
            }
            totalDeposit += params.deposit;
            WETH.deposit{value: params.deposit}();
            
            Struct.CreateStreamParams memory createParams = Struct.CreateStreamParams({
                sender: params.sender,
                recipient: params.recipient,
                deposit: params.deposit,
                tokenAddress: address(WETH),
                startTime: params.startTime,
                stopTime: params.stopTime,
                interval: params.interval,
                cliffAmount: params.cliffAmount,
                cliffTime: params.cliffTime,
                autoWithdrawInterval: params.autoWithdrawInterval,
                autoWithdraw: params.autoWithdraw,
                pauseable: params.pauseable,
                closeable: params.closeable,
                recipientModifiable: params.recipientModifiable
            });

            STREAM.createStream{value: autoWithdrawFee}(
                createParams
            );

            if (params.cliffTime <= block.timestamp && params.cliffAmount > 0) {
                uint256 fee = params.cliffAmount * feeRate / 10000;
                WETH.withdraw(params.cliffAmount);
                _safeTransferETH(params.recipient, params.cliffAmount - fee);
                _safeTransferETH(feeRecipient, fee);
            }
        }

        if (msg.value > totalDeposit + totalAutoWithdrawFee)
            _safeTransferETH(msg.sender, msg.value - totalDeposit - totalAutoWithdrawFee);
    }

    function createStreamETH(
        Struct.CreateStreamParams calldata inputParams
    ) external payable nonReentrant {
        require(inputParams.tokenAddress == address(0x00), "tokenAddress must be ZERO ADDRESS");
        uint256 autoWithdrawFee = 0;
        if (inputParams.autoWithdraw) {
            uint256 autoWithdrawFeeForOnce = STREAM.autoWithdrawFeeForOnce();
            autoWithdrawFee = autoWithdrawFeeForOnce * 
                ((inputParams.stopTime - inputParams.startTime) / inputParams.autoWithdrawInterval + 1);
        }
        
        WETH.deposit{value: inputParams.deposit}();

        Struct.CreateStreamParams memory createParams = Struct.CreateStreamParams({
            sender: inputParams.sender,
            recipient: inputParams.recipient,
            deposit: inputParams.deposit,
            tokenAddress: address(WETH),
            startTime: inputParams.startTime,
            stopTime: inputParams.stopTime,
            interval: inputParams.interval,
            cliffAmount: inputParams.cliffAmount,
            cliffTime: inputParams.cliffTime,
            autoWithdrawInterval: inputParams.autoWithdrawInterval,
            autoWithdraw: inputParams.autoWithdraw,
            pauseable: inputParams.pauseable,
            closeable: inputParams.closeable,
            recipientModifiable: inputParams.recipientModifiable
        });

        STREAM.createStream{value: autoWithdrawFee}(
            createParams
            // msg.sender,
            // recipient,
            // deposit,
            // address(WETH),
            // startTime,
            // stopTime,
            // interval,
            // cliffAmount,
            // cliffTime,
            // autoWithdrawInterval,
            // autoWithdraw,
            // pauseable,
            // closeable,
            // recipientModifiable
        );

        if (inputParams.cliffTime <= block.timestamp && inputParams.cliffAmount > 0) {
            uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
            address feeRecipient = STREAM.feeRecipient();
            uint256 fee = inputParams.cliffAmount * feeRate / 10000;
            WETH.withdraw(inputParams.cliffAmount);
            _safeTransferETH(inputParams.recipient, inputParams.cliffAmount - fee);
            _safeTransferETH(feeRecipient, fee);
        }

        if (msg.value > inputParams.deposit + autoWithdrawFee)
        {
            _safeTransferETH(msg.sender, msg.value - inputParams.deposit - autoWithdrawFee);
        }
    }

    function batchExtendStreamETH(
        uint256[] calldata streamIds,
        uint256[] calldata newStopTimes
    ) external payable nonReentrant {
        require(streamIds.length == newStopTimes.length, "array length not equal");

        uint256 totalDeposit = 0;
        uint256 totalAutoWithdrawFee = 0;
        uint256 autoWithdrawFeeForOnce = STREAM.autoWithdrawFeeForOnce();
        for (uint256 i = 0; i < streamIds.length; i++) {
            Struct.Stream memory stream = STREAM.getStream(streamIds[i]);
            uint256 duration = newStopTimes[i] - stream.stopTime;
            uint256 delta = duration / stream.interval;
            require(delta * stream.interval == duration, "stop time not multiple of interval");

            uint256 newDeposit = delta * stream.ratePerInterval;
            totalDeposit += newDeposit;

            uint256 autoWithdrawFee = 0;
            if (stream.autoWithdraw) {
                autoWithdrawFee = autoWithdrawFeeForOnce * (duration / stream.autoWithdrawInterval + 1);
                totalAutoWithdrawFee += autoWithdrawFee;
            }

            WETH.deposit{value: newDeposit}();
            STREAM.extendStream{value: autoWithdrawFee}(streamIds[i], newStopTimes[i]);
        }

        if (msg.value > totalDeposit + totalAutoWithdrawFee)
            _safeTransferETH(msg.sender, msg.value - totalDeposit - totalAutoWithdrawFee);
    }

    function extendStreamETH(
        uint256 streamId,
        uint256 newStopTime
    ) external payable nonReentrant {
        Struct.Stream memory stream = STREAM.getStream(streamId);

        uint256 duration = newStopTime - stream.stopTime;
        uint256 delta = duration / stream.interval;
        require(delta * stream.interval == duration, "stop time not multiple of interval");

        /* new deposit*/
        uint256 newDeposit = delta * stream.ratePerInterval;

        /* auto withdraw fee */
        uint256 autoWithdrawFee = 0;
        if (stream.autoWithdraw) {
            uint256 autoWithdrawFeeForOnce = STREAM.autoWithdrawFeeForOnce();
            autoWithdrawFee = autoWithdrawFeeForOnce * (duration / stream.autoWithdrawInterval + 1);
        }

        WETH.deposit{value: newDeposit}();
        STREAM.extendStream{value: autoWithdrawFee}(streamId, newStopTime);

        if (msg.value > newDeposit + autoWithdrawFee) 
            _safeTransferETH(msg.sender, msg.value - newDeposit - autoWithdrawFee);
    }

    function batchWithdrawFromStreamETH(uint256[] calldata streamIds) external nonReentrant {
        uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
        address feeRecipient = STREAM.feeRecipient();
        for (uint256 i = 0; i < streamIds.length; i++) {
            Struct.Stream memory stream = STREAM.getStream(streamIds[i]);

            uint256 balance = STREAM.balanceOf(streamIds[i], stream.recipient);

            STREAM.withdrawFromStream(streamIds[i]);
            if (balance > 0){
                uint256 fee = balance * feeRate / 10000;
                WETH.withdraw(balance);
                _safeTransferETH(stream.recipient, balance - fee);
                _safeTransferETH(feeRecipient, fee);
            }
        }
    }

    function withdrawFromStreamETH(uint256 streamId) external nonReentrant {
        Struct.Stream memory stream = STREAM.getStream(streamId);

        uint256 balance = STREAM.balanceOf(streamId, stream.recipient);

        STREAM.withdrawFromStream(streamId);
        if (balance > 0){
            uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
            uint256 fee = balance * feeRate / 10000;
            address feeRecipient = STREAM.feeRecipient();
            WETH.withdraw(balance);
            _safeTransferETH(stream.recipient, balance - fee);
            _safeTransferETH(feeRecipient, fee);
        }
    }

    function batchCloseStreamETH(uint256[] calldata streamIds) external nonReentrant {
        uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
        address feeRecipient = STREAM.feeRecipient();
        for (uint256 i = 0; i < streamIds.length; i++) {
            Struct.Stream memory stream = STREAM.getStream(streamIds[i]);

            uint256 senderBalance = STREAM.balanceOf(streamIds[i], stream.sender);
            uint256 recipientBalance = STREAM.balanceOf(streamIds[i], stream.recipient);

            STREAM.closeStream(streamIds[i]);
            WETH.withdraw(senderBalance + recipientBalance);
            if (senderBalance > 0) {
                _safeTransferETH(stream.sender, senderBalance);
            }
            if (recipientBalance > 0) {
                uint256 fee = recipientBalance * feeRate / 10000;
                _safeTransferETH(stream.recipient, recipientBalance - fee);
                _safeTransferETH(feeRecipient, fee);
            }
        }
    }

    function closeStreamETH(uint256 streamId) external nonReentrant {
        Struct.Stream memory stream = STREAM.getStream(streamId);

        uint256 senderBalance = STREAM.balanceOf(streamId, stream.sender);
        uint256 recipientBalance = STREAM.balanceOf(streamId, stream.recipient);

        STREAM.closeStream(streamId);
        WETH.withdraw(senderBalance + recipientBalance);
        if (senderBalance > 0) {
            _safeTransferETH(stream.sender, senderBalance);
        }
        if (recipientBalance > 0) {
            uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
            uint256 fee = recipientBalance * feeRate / 10000;
            address feeRecipient = STREAM.feeRecipient();
            _safeTransferETH(stream.recipient, recipientBalance - fee);
            _safeTransferETH(feeRecipient, fee);
        }
    }

    function batchPauseStreamETH(uint256[] calldata streamIds) external nonReentrant {
        uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
        address feeRecipient = STREAM.feeRecipient();
        for (uint256 i = 0; i < streamIds.length; i++) {
            Struct.Stream memory stream = STREAM.getStream(streamIds[i]);

            uint256 balance = STREAM.balanceOf(streamIds[i], stream.recipient);

            STREAM.pauseStream(streamIds[i]);
            if (balance > 0) {
                uint256 fee = balance * feeRate / 10000;
                WETH.withdraw(balance);
                _safeTransferETH(stream.recipient, balance - fee);
                _safeTransferETH(feeRecipient, fee);
            }
        }
    }

    function pauseStreamETH(uint256 streamId) public nonReentrant {
        Struct.Stream memory stream = STREAM.getStream(streamId);

        uint256 balance = STREAM.balanceOf(streamId, stream.recipient);

        STREAM.pauseStream(streamId);
        if (balance > 0) {
            uint256 feeRate = STREAM.tokenFeeRate(address(WETH));
            uint256 fee = balance * feeRate / 10000;
            address feeRecipient = STREAM.feeRecipient();
            WETH.withdraw(balance);
            _safeTransferETH(stream.recipient, balance - fee);
            _safeTransferETH(feeRecipient, fee);
        }
    }

    /**
     * @dev transfer ETH to an address, revert if it fails.
     * @param to recipient of the transfer
     * @param value the amount to send
     */
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    /**
     * @dev transfer ERC20 from the utility contract, for ERC20 recovery in case of stuck tokens due
     * direct transfers to the contract address.
     * @param token token to transfer
     * @param to recipient of the transfer
     * @param amount amount to send
     */
    function emergencyTokenTransfer(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev transfer native Ether from the utility contract, for native Ether recovery in case of stuck Ether
     * due to selfdestructs or ether transfers to the pre-computed contract address before deployment.
     * @param to recipient of the transfer
     * @param amount amount to send
     */
    function emergencyEtherTransfer(address to, uint256 amount) external onlyOwner {
        _safeTransferETH(to, amount);
    }

    /**
     * @dev Get WETH address used by WrappedTokenGatewayV3
     */
    function getWETHAddress() external view returns (address) {
        return address(WETH);
    }

    /**
     * @dev Only WETH contract is allowed to transfer ETH here. Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(WETH) || msg.sender == address(STREAM), 'Receive not allowed');
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert('Fallback not allowed');
    }
}
