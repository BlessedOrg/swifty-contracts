// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract StructsLibrary {
    struct ILotteryV1BaseConfig {
        address _seller;
        address _gelatoVrfOperator;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        address _usdcContractAddr;
        address _nftContractAddr;
        address _multisigWalletAddress;
        address _prevPhaseContractAddr;
    }

    struct ILotteryV2BaseConfig {
        address _gelatoVrfOperator;
        address _blessedOperator;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        uint256 _rollPrice;
        uint256 _rollTolerance;
        address _usdcContractAddr;
        address _nftContractAddr;
        address _multisigWalletAddress;
        address _prevPhaseContractAddr;
    }

    struct IAuctionV1BaseConfig {
        address _seller;
        address _gelatoVrfOperator;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        uint256 _priceIncreaseStep;
        address _usdcContractAddr;
        address _nftContractAddr;
        address _multisigWalletAddress;
        address _prevPhaseContractAddr;
    }

    struct IAuctionV2BaseConfig {
        address _seller;
        address _owner;
        uint256 _ticketAmount;
        uint256 _ticketPrice;
        address _usdcContractAddr;
        address _nftContractAddr;
        address _multisigWalletAddress;
        address _prevPhaseContractAddr;
    }
}