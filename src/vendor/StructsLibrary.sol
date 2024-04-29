// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract StructsLibrary {
    struct ILotteryBaseConfig {
        address _seller;
        address _operator;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        uint256 _finishAt;
        address _usdcContractAddr;
        address _multisigWalletAddress;
    }

    struct IAuctionBaseConfig {
        address _seller;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        uint256 _finishAt;
        address _auctionV1Clone;
        address _usdcContractAddr;
        address _multisigWalletAddress;
    }
}