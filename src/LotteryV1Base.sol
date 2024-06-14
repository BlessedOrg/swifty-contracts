// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";

contract LotteryV1Base is GelatoVRFConsumerBase, Ownable(msg.sender), ERC2771Context(0xd8253782c45a12053594b9deB72d8e8aB2Fca54c) {
    function initialize(StructsLibrary.ILotteryBaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._blessedOperator;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        minimumDepositAmount = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;

        initialized = true;
    }

    bool public initialized = false;

    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED,
        VRF_REQUESTED,
        VRF_COMPLETED
    }

    LotteryState public lotteryState;

    address public multisigWalletAddress;
    address public seller;
    address public operatorAddr;

    uint256 public minimumDepositAmount;
    uint256 public numberOfTickets;
    uint256 public randomNumber;
    address[] private eligibleParticipants;
    mapping(address => bool) public hasMinted;

    mapping(address => uint256) public deposits;
    mapping(address => bool) public winners;
    address[] public winnerAddresses;
    address[] private participants;

    address public nftContractAddr;
    address public usdcContractAddr;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();
    event RandomRequested(address indexed requester);
    event RandomFullfiled(uint256 number);

    modifier onlySeller() {
        require(_msgSender() == seller, "Only seller can call this function");
        _;
    }

    modifier lotteryNotStarted() {
        require(lotteryState == LotteryState.NOT_STARTED, "Lottery is in active state");
        _;
    }

    modifier lotteryStarted() {
        require(lotteryState == LotteryState.ACTIVE, "Lottery is not active");
        _;
    }

    modifier lotteryEnded() {
        require(lotteryState == LotteryState.ENDED, "Lottery is not ended yet");
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
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function deposit(uint256 amount) public payable lotteryStarted {
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount > 0, "No funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);

        if (deposits[_msgSender()] == 0) {
            participants.push(_msgSender());
        }
        deposits[_msgSender()] += amount;
    }

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    function getEligibleParticipants() public view returns (address[] memory) {
        return eligibleParticipants;
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

    function setWinner(address _winner) internal {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
    }

    function buyerWithdraw() public lotteryEnded {
        require(!winners[_msgSender()], "Winners cannot withdraw");

        uint256 amount = deposits[_msgSender()];
        require(amount > 0, "No funds to withdraw");

        deposits[_msgSender()] = 0;
        IERC20(usdcContractAddr).transfer(_msgSender(), amount);
    }

    function sellerWithdraw() public onlySeller() {
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

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    }

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory) internal override {
        randomNumber = randomness;
        emit RandomFullfiled(randomness);
    }

    function selectWinners() external onlySeller lotteryStarted {
        require(numberOfTickets > 0, "No tickets left to allocate");
        checkEligibleParticipants();

        if(numberOfTickets >= eligibleParticipants.length) {
            // If demand is less than or equal to supply, everyone wins
            for (uint256 i = 0; i < eligibleParticipants.length; i++) {
                address selectedWinner = eligibleParticipants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
            // Clear the participants list since all are winners
            delete eligibleParticipants;
            numberOfTickets = 0;
        } else {
            // Shuffle the array of participants
            for (uint j = 0; j < eligibleParticipants.length; j++) {
                uint n = j + randomNumber % (eligibleParticipants.length - j);
                address temp = eligibleParticipants[n];
                eligibleParticipants[n] = eligibleParticipants[j];
                eligibleParticipants[j] = temp;
            }

            // Select the first `numberOfTickets` winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                address selectedWinner = eligibleParticipants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }

            // Remove the winners from the participants list by shifting non-winners up
            uint256 shiftIndex = 0;
            for (uint256 i = numberOfTickets; i < eligibleParticipants.length; i++) {
                eligibleParticipants[shiftIndex] = eligibleParticipants[i];
                shiftIndex++;
            }
            for (uint256 i = shiftIndex; i < eligibleParticipants.length; i++) {
                eligibleParticipants.pop();
            }

            numberOfTickets = 0;
        }

        if (numberOfTickets == 0) {
            emit LotteryEnded();
            lotteryState = LotteryState.ENDED;
        }
    }

    function setMinimumDepositAmount(uint256 _amount) public onlySeller {
        minimumDepositAmount = _amount;
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
    }

    function startLottery() public onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
    }

    function endLottery() public onlySeller {
        changeLotteryState(LotteryState.ENDED);
        // Additional logic for ending the lottery
        // Process winners, mint NFT tickets, etc.
    }

    function getDepositedAmount(address participant) external view returns (uint256) {
        return deposits[participant];
    }

    // Function to check and mark eligible participants
    function checkEligibleParticipants() internal {
        for (uint256 i = 0; i < participants.length; i++) {
            uint256 depositedAmount = deposits[participants[i]];
            if (depositedAmount >= minimumDepositAmount) {
                // Mark this participant as eligible for the lottery
                eligibleParticipants.push(participants[i]);
            }
        }
    }

    function removeParticipant(uint256 index) internal {
        require(index < eligibleParticipants.length, "Index out of bounds");

        // If the winner is not the last element, swap it with the last element
        if (index < eligibleParticipants.length - 1) {
            eligibleParticipants[index] = eligibleParticipants[eligibleParticipants.length - 1];
        }

        // Remove the last element (now the winner)
        eligibleParticipants.pop();
    }

    function isParticipantEligible(address participant) public view returns (bool) {
        for (uint256 i = 0; i < eligibleParticipants.length; i++) {
            if (eligibleParticipants[i] == participant) {
                return true;
            }
        }
        return false;
    }

    function mintMyNFT() public hasNotMinted lotteryEnded {
        require(isWinner(_msgSender()), "Caller is not a winner");
        uint256 remainingBalance = deposits[_msgSender()] - minimumDepositAmount;
        deposits[_msgSender()] = 0;
        hasMinted[_msgSender()] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
        if (remainingBalance > 0) {
            IERC20(usdcContractAddr).transfer(_msgSender(), remainingBalance);
        }
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }

    function transferNonWinnerDeposits(address lotteryV2addr) public onlySeller {
        for (uint256 i = 0; i < eligibleParticipants.length; i++) {
            uint256 currentDeposit = deposits[eligibleParticipants[i]];
            deposits[eligibleParticipants[i]] = 0;
            IERC20(usdcContractAddr).transfer(lotteryV2addr, currentDeposit);
            ILotteryV2(lotteryV2addr).transferDeposit(eligibleParticipants[i], currentDeposit);
        }
        delete eligibleParticipants;
    }
}
