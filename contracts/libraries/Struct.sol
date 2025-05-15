// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.20;

library Struct {

    enum Capability {
        None,       //0
        Sender,
        Recipient,
        Both
    }

    struct Stream {
        address onBehalfOf;
        address sender;
        address recipient;
        uint256 deposit;
        address tokenAddress;
        uint256 startTime;
        uint256 stopTime;
        uint256 interval;
        uint256 ratePerInterval;
        uint256 remainingBalance;
        uint256 lastWithdrawTime;
        uint256 createAt;
        uint256 autoWithdrawInterval;
        bool autoWithdraw;
        bool closed;
        bool isEntity;
        CliffInfo cliffInfo;
        FeatureInfo featureInfo;
        PauseInfo pauseInfo;
    }

    struct CliffInfo {
        uint256 cliffAmount;
        uint256 cliffTime;
        bool cliffDone;
    }

    struct FeatureInfo {
        Capability pauseable;
        Capability closeable;
        Capability recipientModifiable;
    }

    struct PauseInfo {
        uint256 pauseAt;
        uint256 accPauseTime;
        address pauseBy;
        bool isPaused;
    }

    struct GlobalParams {
        address weth;
        address gateway;
        address feeRecipient;
        address autoWithdrawAccount;
        uint256 autoWithdrawFeeForOnce;
        uint256 tokenFeeRate;
    }

    struct CreateStreamParams {
        address sender;
        address recipient;
        uint256 deposit;
        address tokenAddress;
        uint256 startTime;
        uint256 stopTime;
        uint256 interval;
        uint256 cliffAmount;
        uint256 cliffTime;
        uint256 autoWithdrawInterval;
        bool autoWithdraw;
        Capability pauseable;
        Capability closeable;
        Capability recipientModifiable;
    }
}