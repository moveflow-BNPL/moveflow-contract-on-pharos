// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Struct} from "./Struct.sol";

library WithdrawLogic {
    using SafeERC20 for IERC20;

    /**
     * @notice Emits when the recipient of a stream withdraws a portion or all their pro rata share of the stream.
     */
    event WithdrawFromStream(uint256 indexed streamId, address indexed operator, uint256 recipientBalance);

    function withdraw(
        uint256 streamId,
        uint256 delta,
        uint256 balance,
        Struct.GlobalParams memory globalParams,
        Struct.Stream storage stream
    )
        internal
    {
        require(stream.pauseInfo.isPaused == false, "stream is paused");
        require(stream.closed == false, "stream is closed");

        stream.remainingBalance = stream.remainingBalance - balance;
        if (delta > 0) {
            stream.lastWithdrawTime += stream.interval * delta + stream.pauseInfo.accPauseTime;
            stream.pauseInfo.accPauseTime = 0;
        }

        if (globalParams.weth == stream.tokenAddress && msg.sender == stream.onBehalfOf) {
            IERC20(stream.tokenAddress).safeTransfer(stream.onBehalfOf, balance);
        } else {
            uint256 fee = balance * globalParams.tokenFeeRate / 10000;
            IERC20(stream.tokenAddress).safeTransfer(globalParams.feeRecipient, fee);
            IERC20(stream.tokenAddress).safeTransfer(stream.recipient, balance - fee);
        }

        /* cliff */
        if (stream.cliffInfo.cliffDone == false && stream.cliffInfo.cliffTime <= block.timestamp) {
            // uint256 cliffAmountFee = stream.cliffAmount * _tokenFeeRate[stream.tokenAddress] / 10000;
            // IERC20(stream.tokenAddress).safeTransfer(_feeRecipient, cliffAmountFee);
            // IERC20(stream.tokenAddress).safeTransfer(stream.recipient, stream.cliffAmount - cliffAmountFee);
            stream.cliffInfo.cliffDone = true;
        }

        emit WithdrawFromStream(streamId, msg.sender, balance);
    }
}