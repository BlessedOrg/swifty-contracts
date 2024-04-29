// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "../vendor/StructsLibrary.sol";

interface IAuctionBase {
    function initialize(StructsLibrary.IAuctionBaseConfig memory config) external;
}