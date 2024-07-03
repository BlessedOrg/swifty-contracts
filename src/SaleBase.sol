// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import { Initializable } from "../lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import { StructsLibrary } from "./vendor/StructsLibrary.sol";
import "src/interfaces/IERC20.sol";

contract SaleBase is Initializable, Ownable(msg.sender), ERC2771Context(0xd8253782c45a12053594b9deB72d8e8aB2Fca54c) {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED
    }

    LotteryState public lotteryState;
    address public multisigWalletAddress;
    address public seller;
    uint256 public numberOfTickets;
    uint256 public ticketPrice;
    mapping(address => bool) public hasMinted;
    mapping(address => uint256) public deposits;
    mapping(address => bool) public winners;
    address[] public winnerAddresses;
    address[] internal participants;
    address public nftContractAddr;
    address public usdcContractAddr;

    event LotteryStarted();
    event LotteryEnded();
    event WinnerSelected(address indexed winner);
    event BuyerWithdrew(address indexed buyer, uint256 indexed amount);
    event BuyerDeposited(address indexed buyer, uint256 indexed amount);
    event DepositsReturned(uint256 returnedDepositsCount);

    modifier onlySeller() {
        require(_msgSender() == seller, "Only seller can call this function");
        _;
    }

    modifier lotteryNotStarted() {
        require(lotteryState == LotteryState.NOT_STARTED, "Sale is in active state");
        _;
    }

    modifier lotteryStarted() {
        require(lotteryState == LotteryState.ACTIVE, "Sale is not active");
        _;
    }

    modifier lotteryEnded() {
        require(lotteryState == LotteryState.ENDED, "Sale is not ended yet");
        _;
    }

    modifier hasNotMinted() {
        require(!hasMinted[_msgSender()], "NFT already minted");
        _;
    }

    modifier whenLotteryNotActive() {
        require(lotteryState != LotteryState.ACTIVE, "Lottery is currently active");
        _;
    }

    function setSeller(address _seller) external onlySeller {
        seller = _seller;
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        return ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    function changeLotteryState(LotteryState _newState) public onlySeller {
        lotteryState = _newState;
    }

    function isWinner(address _participant) public view returns (bool) {
        return winners[_participant];
    }

    function getWinners() public view returns (address[] memory) {
        return winnerAddresses;
    }

    function setWinner(address _winner) internal virtual {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
        emit WinnerSelected(_winner);
    }

    function buyerWithdraw() public virtual lotteryEnded {
        require(!winners[_msgSender()], "Winners cannot withdraw");
        uint256 amount = deposits[_msgSender()];
        require(amount > 0, "No funds to withdraw");
        deposits[_msgSender()] = 0;
        IERC20(usdcContractAddr).transfer(_msgSender(), amount);
        emit BuyerWithdrew(_msgSender(), amount);
    }

    function sellerWithdraw() public virtual onlySeller {
        require(lotteryState == LotteryState.ENDED, "Lottery not ended");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < winnerAddresses.length; i++) {
            address winner = winnerAddresses[i];
            totalAmount += deposits[winner];
            deposits[winner] = 0; // Prevent double withdrawal
        }
        uint256 protocolTax = (totalAmount * 5) / 100; // 5% tax
        uint256 amountToSeller = totalAmount - protocolTax;
        IERC20(usdcContractAddr).transfer(multisigWalletAddress, protocolTax);
        IERC20(usdcContractAddr).transfer(seller, amountToSeller);
    }

    function startLottery() public onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
        emit LotteryStarted();
    }

    function endLottery() public virtual onlySeller {
        changeLotteryState(LotteryState.ENDED);
        emit LotteryEnded();
    }

    function getDepositedAmount(address participant) external virtual view returns (uint256) {
        return deposits[participant];
    }

    function transferDepositsBack() virtual internal onlySeller lotteryEnded {
        uint256 participantsLength = participants.length;
        address[] memory participantsCopy = new address[](participantsLength);
        for (uint256 i = 0; i < participantsLength; i++) {
            participantsCopy[i] = participants[i];
        }
        for (uint256 i = 0; i < participantsLength; i++) {
            address participant = participantsCopy[i];
            uint256 depositAmount = deposits[participant];
            deposits[participant] = 0;

            if (isWinner(participant)) {
                uint256 winnerRemainingDeposit = depositAmount - ticketPrice;
                IERC20(usdcContractAddr).transfer(participant, winnerRemainingDeposit);
            } else {
                IERC20(usdcContractAddr).transfer(participant, depositAmount);
            }
        }
        delete participants;
        emit DepositsReturned(participantsLength);
    }
}
