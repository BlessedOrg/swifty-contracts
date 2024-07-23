pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { Clones } from "../lib/openzeppelin-contracts/contracts/proxy/Clones.sol";
import { StructsLibrary } from "./vendor/StructsLibrary.sol";
import { ILotteryV1Base, ILotteryV2Base, IAuctionV1Base, IAuctionV2Base } from "./interfaces/ISaleBase.sol";
import { INFTLotteryTicket } from "./interfaces/INFTLotteryTicket.sol";

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
        string _name;
        string _symbol;
        uint256 _lotteryV2RollPrice;
        uint256 _lotteryV2RollTolerance;
        uint256 _auctionV1PriceIncreaseStep;
    }

    function createSale(SaleConfig memory config) external {
        // deploy NFT contracts per each sale option
        address nftLotteryV1 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftLotteryV1).initialize(config._uri, false, address(this), config._name, config._symbol);
        address nftLotteryV2 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftLotteryV2).initialize(config._uri, false, address(this), config._name, config._symbol);
        address nftAuctionV1 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftAuctionV1).initialize(config._uri, true, address(this), config._name, config._symbol);
        address nftAuctionV2 = Clones.clone(nftTicket);
        INFTLotteryTicket(nftAuctionV2).initialize(config._uri, true, address(this), config._name, config._symbol);

        // Deploy LotteryV1 and link NFT
        address lotteryV1Clone = Clones.clone(lotteryV1);
        StructsLibrary.ILotteryV1BaseConfig memory lotteryV1Config = StructsLibrary.ILotteryV1BaseConfig({
            _seller: config._seller,
            _gelatoVrfOperator: config._gelatoVrfOperator,
            _owner: address(this),
            _ticketAmount: config._lotteryV1TicketAmount,
            _ticketPrice: config._ticketPrice,
            _nftContractAddr: nftLotteryV1,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: lotteryV1Clone
        });
        ILotteryV1Base(lotteryV1Clone).initialize(lotteryV1Config);
        INFTLotteryTicket(nftLotteryV1).setDepositContractAddr(lotteryV1Clone);

        // Deploy LotteryV2 and link NFT
        address lotteryV2Clone = Clones.clone(lotteryV2);
        StructsLibrary.ILotteryV2BaseConfig memory lotteryV2Config = StructsLibrary.ILotteryV2BaseConfig({
            _gelatoVrfOperator: config._gelatoVrfOperator,
            _blessedOperator: config._blessedOperator,
            _owner: address(this),
            _ticketAmount: config._lotteryV2TicketAmount,
            _ticketPrice: config._ticketPrice,
            _rollPrice: config._lotteryV2RollPrice,
            _rollTolerance: config._lotteryV2RollTolerance,
            _nftContractAddr: nftLotteryV2,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: lotteryV1Clone
        });
        ILotteryV2Base(lotteryV2Clone).initialize(lotteryV2Config);
        INFTLotteryTicket(nftLotteryV2).setDepositContractAddr(lotteryV2Clone);

        // Deploy AuctionV1 and link NFT
        address auctionV1Clone = Clones.clone(auctionV1);
        StructsLibrary.IAuctionV1BaseConfig memory auctionV1Config = StructsLibrary.IAuctionV1BaseConfig({
            _seller: config._seller,
            _gelatoVrfOperator: config._gelatoVrfOperator,
            _owner: address(this),
            _ticketAmount: config._auctionV1TicketAmount,
            _ticketPrice: config._ticketPrice,
            _priceIncreaseStep: config._auctionV1PriceIncreaseStep,
            _nftContractAddr: nftAuctionV1,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: lotteryV2Clone
        });
        IAuctionV1Base(auctionV1Clone).initialize(auctionV1Config);
        INFTLotteryTicket(nftAuctionV1).setDepositContractAddr(auctionV1Clone);

        // Deploy AuctionV2 and link NFT
        address auctionV2Clone = Clones.clone(auctionV2);
        StructsLibrary.IAuctionV2BaseConfig memory auctionV2Config = StructsLibrary.IAuctionV2BaseConfig({
            _seller: config._seller,
            _owner: address(this),
            _ticketAmount: config._auctionV2TicketAmount,
            _ticketPrice: config._ticketPrice,
            _nftContractAddr: nftAuctionV2,
            _usdcContractAddr: config._usdcContractAddr,
            _multisigWalletAddress: config._multisigWalletAddress,
            _prevPhaseContractAddr: auctionV1Clone
        });
        IAuctionV2Base(auctionV2Clone).initialize(auctionV2Config);
        INFTLotteryTicket(nftAuctionV2).setDepositContractAddr(auctionV2Clone);

        sales[currentIndex] = [
            lotteryV1Clone,
            lotteryV2Clone,
            auctionV1Clone,
            auctionV2Clone
        ];

        currentIndex += 1;
    }
}