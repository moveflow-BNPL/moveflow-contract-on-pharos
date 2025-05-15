// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

import {Struct} from "../libraries/Struct.sol";

interface IStream {
    function tokenFeeRate(address tokenAddress) external view returns (uint256);

    function autoWithdrawFeeForOnce() external view returns (uint256);

    function autoWithdrawAccount() external view returns (address);

    function feeRecipient() external view returns (address);

    function balanceOf(uint256 streamId, address who) external view returns (uint256 balance);

    function getStream(uint256 streamId) external view returns (Struct.Stream memory);

    function tokenlist() external view returns (address[] memory);

    function tokenBalance(address[] calldata tokenAddresses) external view returns (uint256[] memory);

    function createStream(Struct.CreateStreamParams calldata createParams) external payable;

    function extendStream(uint256 streamId, uint256 stopTime) external payable;

    function withdrawFromStream(uint256 streamId) external;

    function closeStream(uint256 streamId) external;

    function pauseStream(uint256 streamId) external;

    function resumeStream(uint256 streamId) external;

    function setNewRecipient(uint256 streamId, address newRecipient) external;
}