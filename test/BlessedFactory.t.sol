// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Test, console2 } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { NFTTicketBase } from "../src/NFTTicketBase.sol";
import { BlessedFactory } from "../src/BlessedFactory.sol";
import { LotteryBase } from "../src/LotteryBase.sol";
import { LotteryV2Base } from "../src/LotteryV2Base.sol";
import { AuctionV1Base } from "../src/AuctionV1Base.sol";
import { AuctionV2Base } from "../src/AuctionV2Base.sol";

contract BlessedFactoryTest is Test {
    uint256 private sellerPrivateKey = 0xa11ce;
    address seller;

    BlessedFactory public blessedFactory;

    function setUp() public {
      seller = vm.addr(sellerPrivateKey);

      vm.startPrank(seller);
      NFTTicketBase nftLotteryTicket = new NFTTicketBase();
      LotteryBase lotteryBase = new LotteryBase();
      LotteryV2Base lotteryV2Base = new LotteryV2Base();
      AuctionV1Base auctionV1Base = new AuctionV1Base();
      AuctionV2Base auctionV2Base = new AuctionV2Base();
      blessedFactory = new BlessedFactory();
      blessedFactory.setBaseContracts(
        address(nftLotteryTicket), 
        address(lotteryBase),
        address(lotteryV2Base),
        address(auctionV1Base),
        address(auctionV2Base)
      );
      vm.stopPrank();
    }

    function test_CreateSaleTest() public {
      vm.startPrank(seller);
      address [4] memory deployedAddrs = blessedFactory.createSale(seller, seller, seller, "http://tokenuri.com/");
      vm.stopPrank();

      assertEq(LotteryBase(deployedAddrs[0]).owner(), seller, "Owner must be seller");
      assertEq(LotteryV2Base(deployedAddrs[1]).owner(), seller, "Owner must be seller");
      assertEq(AuctionV1Base(deployedAddrs[2]).owner(), seller, "Owner must be seller");
      assertEq(AuctionV2Base(deployedAddrs[3]).owner(), seller, "Owner must be seller");

      address lotteryV1nftAddr = LotteryBase(deployedAddrs[0]).nftContractAddr();
      assertNotEq(lotteryV1nftAddr, address(0));
      assertEq(NFTTicketBase(lotteryV1nftAddr).depositContractAddr(), deployedAddrs[0], "NFT must have Lottery linked");
      assertEq(NFTTicketBase(lotteryV1nftAddr).owner(), seller, "NFT must have Lottery linked");

      assertNotEq(LotteryV2Base(deployedAddrs[1]).nftContractAddr(), address(0));
      assertNotEq(AuctionV1Base(deployedAddrs[2]).nftContractAddr(), address(0));
      assertNotEq(AuctionV2Base(deployedAddrs[3]).nftContractAddr(), address(0));
    }
}