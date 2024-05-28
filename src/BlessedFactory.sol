// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { Clones } from "../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { INFTLotteryTicket } from "./interfaces/INFTLotteryTicket.sol";
import { ILotteryBase } from "./interfaces/ILotteryBase.sol";
import { IAuctionBase } from "./interfaces/IAuctionBase.sol";
import { StructsLibrary } from "./vendor/StructsLibrary.sol";

contract BlessedFactory is Ownable(msg.sender) {
    address public nftTicket;
    address public lotteryV1;
    address public lotteryV2;
    address public auctionV1;
    address public auctionV2;

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

    struct SaleConfig {
        address _seller;
        address _gelatoVrfOperator;
        address _blessedOperator;
        address _owner;
        uint256 _lotteryV1TicketAmount;
        uint256 _lotteryV2TicketAmount;
        uint256 _auctionV1TicketAmount;
        uint256 _auctionV2TicketAmount;
        uint256 _ticketPrice;
        string _uri;
        address _usdcContractAddr;
        address _multisigWalletAddress;
    }

    function createSale(SaleConfig memory config) external {
        // deploy NFT contracts per each sale option
        address nftLotteryV1 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftLotteryV1).initialize(config._uri, false, address(this));
        address nftLotteryV2 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftLotteryV2).initialize(config._uri, false, address(this));
        address nftAuctionV1 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftAuctionV1).initialize(config._uri, true, address(this));
        address nftAuctionV2 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftAuctionV2).initialize(config._uri, true, address(this));

        // Deploy LotteryV1 and link NFT
        address lotteryV1Clone = Clones.clone(lotteryV1);
        StructsLibrary.ILotteryBaseConfig memory lotteryV1Config = StructsLibrary.ILotteryBaseConfig({
            _seller: config._seller,
            _gelatoVrfOperator: config._gelatoVrfOperator,
            _blessedOperator: config._blessedOperator,
            _owner: address(this),
            _ticketAmount: config._lotteryV1TicketAmount,
            _ticketPrice: config._ticketPrice,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: lotteryV1Clone
        });
        ILotteryBase(lotteryV1Clone).initialize(lotteryV1Config);
        INFTLotteryTicket(nftLotteryV1).setDepositContractAddr(lotteryV1Clone);
        ILotteryBase(lotteryV1Clone).setNftContractAddr(nftLotteryV1);

        // Deploy LotteryV2 and link NFT
        address lotteryV2Clone = Clones.clone(lotteryV2);
        StructsLibrary.ILotteryBaseConfig memory lotteryV2Config = StructsLibrary.ILotteryBaseConfig({
            _seller: config._seller,
            _gelatoVrfOperator: config._gelatoVrfOperator,
            _blessedOperator: config._blessedOperator,
            _owner: address(this),
            _ticketAmount: config._lotteryV2TicketAmount,
            _ticketPrice: config._ticketPrice,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: lotteryV1Clone
        });
        ILotteryBase(lotteryV2Clone).initialize(lotteryV2Config);
        INFTLotteryTicket(nftLotteryV2).setDepositContractAddr(lotteryV2Clone);
        ILotteryBase(lotteryV2Clone).setNftContractAddr(nftLotteryV2);

//         Deploy AuctionV1 and link NFT
        address auctionV1Clone = Clones.clone(auctionV1);
        StructsLibrary.ILotteryBaseConfig memory auctionV1Config = StructsLibrary.ILotteryBaseConfig({
            _seller: config._seller,
            _gelatoVrfOperator: config._gelatoVrfOperator,
            _blessedOperator: config._blessedOperator,
            _owner: address(this),
            _ticketAmount: config._auctionV1TicketAmount,
            _ticketPrice: config._ticketPrice,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: lotteryV2Clone
        });
        ILotteryBase(auctionV1Clone).initialize(auctionV1Config);
        INFTLotteryTicket(nftAuctionV1).setDepositContractAddr(auctionV1Clone);
        ILotteryBase(auctionV1Clone).setNftContractAddr(nftAuctionV1);

        // Deploy AuctionV2 and link NFT
        address auctionV2Clone = Clones.clone(auctionV2);
        StructsLibrary.IAuctionBaseConfig memory auctionV2Config = StructsLibrary.IAuctionBaseConfig({
            _seller: config._seller,
            _owner: address(this),
            _ticketAmount: config._auctionV2TicketAmount,
            _ticketPrice: config._ticketPrice,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: auctionV1Clone
        });
        IAuctionBase(auctionV2Clone).initialize(auctionV2Config);
        INFTLotteryTicket(nftAuctionV2).setDepositContractAddr(auctionV2Clone);
        ILotteryBase(auctionV2Clone).setNftContractAddr(nftAuctionV2);

        // transfer ownerships to owners
        ILotteryBase(lotteryV1Clone).transferOwnership(config._owner);
        ILotteryBase(lotteryV2Clone).transferOwnership(config._owner);
        ILotteryBase(auctionV1Clone).transferOwnership(config._owner);
        ILotteryBase(auctionV2Clone).transferOwnership(config._owner);
        INFTLotteryTicket(nftLotteryV1).transferOwnership(config._owner);
        INFTLotteryTicket(nftLotteryV2).transferOwnership(config._owner);
        INFTLotteryTicket(nftAuctionV1).transferOwnership(config._owner);
        INFTLotteryTicket(nftAuctionV2).transferOwnership(config._owner);

        sales[currentIndex] = [
            lotteryV1Clone,
            lotteryV2Clone,
            auctionV1Clone,
            auctionV2Clone
        ];

        currentIndex += 1;
    }
}