// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { Clones } from "../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { INFTLotteryTicket } from "./interfaces/INFTLotteryTicket.sol";
import { ILotteryBase } from "./interfaces/ILotteryBase.sol";
import { IAuctionBase } from "./interfaces/IAuctionBase.sol";

contract BlessedFactory is Ownable(msg.sender) {
  address nftTicket;
  address lotteryV1;
  address lotteryV2;
  address auctionV1;
  address auctionV2;

  uint256 public currentIndex;

  mapping(uint256 => address[4]) public sales;

  function setBaseContracts(
    address _nftTicket, 
    address _lotteryV1,
    address _lotteryV2,
    address _auctionV1,
    address _auctionV2
  ) external onlyOwner {
    nftTicket = _nftTicket;
    lotteryV1 = _lotteryV1;
    lotteryV2 = _lotteryV2;
    auctionV1 = _auctionV1;
    auctionV2 = _auctionV2;
  }

  function createSale(address _seller, address _operator, address _owner, string calldata _uri) external returns(address[4] memory) {
    // deploy NFT contracts per each sale option
    address nftLotteryV1 = Clones.clone(nftTicket);
    INFTLotteryTicket(nftLotteryV1).initialize(_uri, false, address(this));
    address nftLotteryV2 = Clones.clone(nftTicket);
    INFTLotteryTicket(nftLotteryV2).initialize(_uri, false, address(this));
    address nftAuctionV1 = Clones.clone(nftTicket);
    INFTLotteryTicket(nftAuctionV1).initialize(_uri, true, address(this));
    address nftAuctionV2 = Clones.clone(nftTicket);
    INFTLotteryTicket(nftAuctionV2).initialize(_uri, true, address(this));

    // Deploy LotteryV1 and link NFT
    address lotteryV1Clone = Clones.clone(lotteryV1);
    ILotteryBase(lotteryV1Clone).initialize(_seller, _operator, address(this));
    INFTLotteryTicket(nftLotteryV1).setDepositContractAddr(lotteryV1Clone);
    ILotteryBase(lotteryV1Clone).setNftContractAddr(nftLotteryV1);

    // Deploy LotteryV2 and link NFT
    address lotteryV2Clone = Clones.clone(lotteryV2);
    ILotteryBase(lotteryV2Clone).initialize(_seller, _operator, address(this));
    INFTLotteryTicket(nftLotteryV2).setDepositContractAddr(lotteryV2Clone);
    ILotteryBase(lotteryV2Clone).setNftContractAddr(nftLotteryV2);

    // Deploy AuctionV1 and link NFT
    address auctionV1Clone = Clones.clone(auctionV1);
    ILotteryBase(auctionV1Clone).initialize(_seller, _operator, address(this));
    INFTLotteryTicket(nftAuctionV1).setDepositContractAddr(auctionV1Clone);
    ILotteryBase(auctionV1Clone).setNftContractAddr(nftAuctionV1);

    // Deploy AuctionV2 and link NFT
    address auctionV2Clone = Clones.clone(auctionV2);
    IAuctionBase(auctionV2Clone).initialize(_seller, address(this));
    INFTLotteryTicket(nftAuctionV2).setDepositContractAddr(auctionV2Clone);
    ILotteryBase(auctionV2Clone).setNftContractAddr(nftAuctionV2);

    // transfer ownerships to owners
    ILotteryBase(lotteryV1Clone).transferOwnership(_owner);
    ILotteryBase(lotteryV2Clone).transferOwnership(_owner);
    ILotteryBase(auctionV1Clone).transferOwnership(_owner);
    ILotteryBase(auctionV2Clone).transferOwnership(_owner);
    INFTLotteryTicket(nftLotteryV1).transferOwnership(_owner);
    INFTLotteryTicket(nftLotteryV2).transferOwnership(_owner);
    INFTLotteryTicket(nftAuctionV1).transferOwnership(_owner);
    INFTLotteryTicket(nftAuctionV2).transferOwnership(_owner);

    sales[currentIndex] = [
      lotteryV1Clone,
      lotteryV2Clone,
      auctionV1Clone,
      auctionV2Clone
    ];

    currentIndex += 1;

    return sales[currentIndex - 1];
  }
}