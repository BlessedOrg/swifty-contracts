// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "../vendor/StructsLibrary.sol";

interface ILotteryBase {
    function initialize(StructsLibrary.ILotteryBaseConfig memory config) external;
    function transferOwnership(address newOwner) external;
    function setNftContractAddr(address _nftContractAddr) external;
}