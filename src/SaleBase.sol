// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "src/interfaces/IERC20.sol";

contract SaleBase is Ownable(msg.sender), ERC2771Context(0xd8253782c45a12053594b9deB72d8e8aB2Fca54c) {
    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED
    }

    LotteryState public lotteryState;
    address public multisigWalletAddress;
    address public seller;
    uint256 public minimumDepositAmount;
    uint256 public numberOfTickets;
    mapping(address => bool) public hasMinted;
    mapping(address => uint256) public deposits;
    mapping(address => bool) public winners;
    address[] public winnerAddresses;
    address[] internal participants;
    address public nftContractAddr;
    address public usdcContractAddr;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();

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

    function setMultisigWalletAddress(address _multisigWalletAddress) public onlyOwner {
        multisigWalletAddress = _multisigWalletAddress;
    }

    function setNftContractAddr(address _nftContractAddr) public onlyOwner {
        nftContractAddr = _nftContractAddr;
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
    }

    function buyerWithdraw() public virtual lotteryEnded {
        require(!winners[_msgSender()], "Winners cannot withdraw");
        uint256 amount = deposits[_msgSender()];
        require(amount > 0, "No funds to withdraw");
        deposits[_msgSender()] = 0;
        IERC20(usdcContractAddr).transfer(_msgSender(), amount);
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

    function setMinimumDepositAmount(uint256 _amount) public onlySeller {
        minimumDepositAmount = _amount;
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public virtual onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
    }

    function startLottery() public virtual onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
        emit LotteryStarted();
    }

    function endLottery() public onlySeller {
        changeLotteryState(LotteryState.ENDED);
        emit LotteryEnded();
    }

    function getDepositedAmount(address participant) external virtual view returns (uint256) {
        return deposits[participant];
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }
}
