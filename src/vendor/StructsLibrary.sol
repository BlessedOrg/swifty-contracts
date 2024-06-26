// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract StructsLibrary {
    struct ILotteryBaseConfig {
        address _gelatoVrfOperator;
        address _blessedOperator;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        address _usdcContractAddr;
        address _multisigWalletAddress;
    }

    struct IAuctionBaseConfig {
        address _seller;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        address _usdcContractAddr;
        address _multisigWalletAddress;
    }
}