// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Struct} from "./Struct.sol";

library ExtendLogic {
    using SafeERC20 for IERC20;

    /**
     * @notice Emits when a stream is successfully extend.
     */
    event ExtendStream(uint256 indexed streamId, address indexed operator, uint256 stopTime, uint256 deposit);

    function extend(
        uint256 streamId, 
        uint256 stopTime,
        uint256 senderValue,
        Struct.GlobalParams memory globalParams,
        Struct.Stream storage stream
    )
        internal
        returns (uint256 autoWithdrawFee)
    {
        require(stopTime > stream.stopTime, "stop time not after the current stop time");
        require(block.timestamp <= stream.stopTime, "the stream is stopped");
        require(stream.pauseInfo.isPaused == false, "stream is paused");
        require(stream.closed == false, "stream is closed");
        require(
            msg.sender == stream.sender || 
            (globalParams.weth == stream.tokenAddress && msg.sender == stream.onBehalfOf), "not allowed to extend the stream"
        );

        uint256 duration = stopTime - stream.stopTime;
        uint256 delta = duration / stream.interval;
        require(delta * stream.interval == duration, "stop time not multiple of interval");

        /* auto withdraw fee */
        if (stream.autoWithdraw) {
            autoWithdrawFee = globalParams.autoWithdrawFeeForOnce * (duration / stream.autoWithdrawInterval + 1);
            require(senderValue >= autoWithdrawFee, "auto withdraw fee no enough");
            payable(globalParams.autoWithdrawAccount).transfer(autoWithdrawFee);
            // payable(msg.sender).transfer(msg.value - autoWithdrawFee);

        }

        uint256 newDeposit = delta * stream.ratePerInterval;

        stream.stopTime = stopTime;
        stream.deposit = stream.deposit + newDeposit;
        stream.remainingBalance = stream.remainingBalance + newDeposit;

        IERC20(stream.tokenAddress).safeTransferFrom(msg.sender, address(this), newDeposit);

        emit ExtendStream(streamId, msg.sender, stopTime, newDeposit);
    }

}