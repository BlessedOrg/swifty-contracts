// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "../vendor/StructsLibrary.sol";

interface ILotteryV1Base {
    function initialize(StructsLibrary.ILotteryV1BaseConfig memory config) external;
    function setSeller(address _seller) external;
    function transferOwnership(address newOwner) external;
    function setNftContractAddr(address _nftContractAddr) external;
}

interface ILotteryV2Base {
    function initialize(StructsLibrary.ILotteryV2BaseConfig memory config) external;
    function setSeller(address _seller) external;
    function transferOwnership(address newOwner) external;
    function setNftContractAddr(address _nftContractAddr) external;
}

interface IAuctionV1Base {
    function initialize(StructsLibrary.IAuctionV1BaseConfig memory config) external;
    function setNftContractAddr(address _nftContractAddr) external;
    function transferOwnership(address newOwner) external;
}

interface IAuctionV2Base {
    function initialize(StructsLibrary.IAuctionV2BaseConfig memory config) external;
    function setNftContractAddr(address _nftContractAddr) external;
    function transferOwnership(address newOwner) external;
}
