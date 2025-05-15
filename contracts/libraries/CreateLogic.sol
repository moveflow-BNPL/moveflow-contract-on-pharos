// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Struct} from "./Struct.sol";

library CreateLogic {
    using SafeERC20 for IERC20;

    /**
     * @notice Emits when a stream is successfully created.
     */
    event CreateStream(
        uint256 indexed streamId,
        address indexed sender,
        address indexed recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint256 interval,
        uint256 cliffAmount,
        uint256 cliffTime,
        uint256 autoWithdrawInterval,
        bool autoWithdraw,
        uint8 pauseable,
        uint8 closeable,
        uint8 recipientModifiable
    );

    function create(
        uint256 streamId,
        uint256 senderValue,
        Struct.GlobalParams memory globalParams,
        Struct.CreateStreamParams calldata createParams,
        mapping(uint256 => Struct.Stream) storage streams
    ) internal returns (uint256 autoWithdrawFee) {
        verifyCreateStreamParams(createParams);

        uint256 ratePerInterval = calculateRatePerInterval(createParams);

        /* Create and store the stream object. */
        streams[streamId] = Struct.Stream({
            onBehalfOf: address(0x00),
            deposit: createParams.deposit,
            ratePerInterval: ratePerInterval,
            remainingBalance: createParams.deposit,
            startTime: createParams.startTime,
            stopTime: createParams.stopTime,
            interval: createParams.interval,
            lastWithdrawTime: createParams.startTime,
            recipient: createParams.recipient,
            sender: createParams.sender,
            tokenAddress: createParams.tokenAddress,
            createAt: block.timestamp,
            autoWithdrawInterval: createParams.autoWithdrawInterval,
            autoWithdraw: createParams.autoWithdraw,
            closed: false,
            isEntity: true,
            cliffInfo: Struct.CliffInfo({
                cliffAmount: createParams.cliffAmount,
                cliffTime: createParams.cliffTime,
                cliffDone: false
            }),
            featureInfo: Struct.FeatureInfo({
                pauseable: createParams.pauseable,
                closeable: createParams.closeable,
                recipientModifiable: createParams.recipientModifiable
            }),
            pauseInfo: Struct.PauseInfo({
                pauseAt: 0,
                accPauseTime: 0,
                pauseBy: address(0x00),
                isPaused: false
            })
        });

        if (msg.sender == globalParams.gateway) {
            streams[streamId].onBehalfOf = globalParams.gateway;
        }

        IERC20(createParams.tokenAddress).safeTransferFrom(msg.sender, address(this), createParams.deposit);

        /* auto withdraw fee */
        if (createParams.autoWithdraw) {
            autoWithdrawFee = globalParams.autoWithdrawFeeForOnce * 
                                     ((createParams.stopTime - createParams.startTime) / createParams.autoWithdrawInterval + 1);
            require(senderValue >= autoWithdrawFee, "auto withdraw fee no enough");
            payable(globalParams.autoWithdrawAccount).transfer(autoWithdrawFee);
            // payable(createParams.sender).transfer(msg.value - autoWithdrawFee);
        }

        /* send cliff to recipient */
        if (createParams.cliffAmount == 0) {
            streams[streamId].cliffInfo.cliffDone = true;
        } else if (createParams.cliffTime <= block.timestamp) {
            if (msg.sender == globalParams.gateway) {
                IERC20(createParams.tokenAddress).safeTransfer(msg.sender, createParams.cliffAmount);
            } else {
                uint256 cliffAmountFee = createParams.cliffAmount * globalParams.tokenFeeRate / 10000;
                uint256 recipientAmount = createParams.cliffAmount - cliffAmountFee;
                IERC20(createParams.tokenAddress).safeTransfer(globalParams.feeRecipient, cliffAmountFee);
                IERC20(createParams.tokenAddress).safeTransfer(createParams.recipient, recipientAmount);
            }
            // IERC20(createParams.tokenAddress).safeTransfer(createParams.recipient, recipientAmount);
            streams[streamId].cliffInfo.cliffDone = true;
            streams[streamId].remainingBalance -= createParams.cliffAmount;
        }

        /* emit CreateStream event */
        emitCreateStreamEvent(streamId, streams[streamId]);
    }

    function verifyCreateStreamParams(
        Struct.CreateStreamParams memory createParams
    ) internal view {
        require(createParams.recipient != address(0x00), "stream to the zero address");
        require(createParams.recipient != address(this), "stream to the contract itself");
        require(createParams.recipient != createParams.sender, "stream to the caller");
        require(createParams.deposit > 0, "deposit is zero");
        require(createParams.startTime >= block.timestamp, "start time before block.timestamp");
        require(createParams.stopTime > createParams.startTime, "stop time before the start time");
        require(createParams.cliffAmount <= createParams.deposit, "cliff amount larger than deposit");
    }

    function calculateRatePerInterval(
        Struct.CreateStreamParams memory createParams
    ) internal pure returns (uint256 ratePerInterval) {
        uint256 duration = createParams.stopTime - createParams.startTime;
        uint256 delta = duration / createParams.interval;
        require(delta * createParams.interval == duration, "deposit smaller than duration");

        ratePerInterval = (createParams.deposit - createParams.cliffAmount) / delta;
        require(ratePerInterval * delta == createParams.deposit - createParams.cliffAmount, "deposit not multiple of time delta");
    }

    function emitCreateStreamEvent(
        uint256 streamId,
        Struct.Stream memory stream
    ) internal {
        emit CreateStream(
            streamId, 
            stream.sender, 
            stream.recipient, 
            stream.deposit, 
            stream.tokenAddress, 
            stream.startTime, 
            stream.stopTime, 
            stream.interval,
            stream.cliffInfo.cliffAmount,
            stream.cliffInfo.cliffTime,
            stream.autoWithdrawInterval,
            stream.autoWithdraw,
            uint8(stream.featureInfo.pauseable),
            uint8(stream.featureInfo.closeable),
            uint8(stream.featureInfo.recipientModifiable)
        );
    }
}